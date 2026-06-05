package com.liita.liita

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import androidx.core.app.ActivityCompat
import kotlinx.coroutines.*
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue

class MeshForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "liita_mesh_channel"
        const val NOTIFICATION_ID = 1
        val SERVICE_UUID: UUID = UUID.fromString("6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
        val PROFILE_CHAR_UUID: UUID = UUID.fromString("6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
        const val TAG = "MeshForegroundService"
    }

    private val binder = LocalBinder()

    // Main-thread handler — Android BLE stack requires BLE ops on the main thread
    private val mainHandler = Handler(Looper.getMainLooper())

    // Core BLE Components
    private var bluetoothManager: BluetoothManager? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothLeAdvertiser: BluetoothLeAdvertiser? = null
    private var bluetoothLeScanner: BluetoothLeScanner? = null
    private var gattServer: BluetoothGattServer? = null

    // State
    private var localDeviceId: String = ""
    private var localProfileJson: String = ""
    private var isRunning = false
    private var currentMode = 0 // 0=continuous, 1=foreground, 2=background

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var dutyCycleJob: Job? = null

    // Helpers
    private val peerRegistry = BlePeerRegistry()
    private val dedupCache = DeduplicationCache()
    private lateinit var relayController: RelayController

    // Bug 3 fix: Connection flood guard — tracks MAC addresses mid-connection
    private val connectingDevices = ConcurrentHashMap<String, Boolean>()

    // Bug 6 fix: Serial GATT write queue
    private data class WriteRequest(val gatt: BluetoothGatt, val payload: ByteArray)
    private val writeQueue = ConcurrentLinkedQueue<WriteRequest>()
    @Volatile private var isWriting = false

    // Callbacks to Flutter
    var onPeerDiscovered: ((String) -> Unit)? = null
    var onPacketReceived: ((String) -> Unit)? = null

    inner class LocalBinder : Binder() {
        fun getService(): MeshForegroundService = this@MeshForegroundService
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Liita Mesh Active")
            .setContentText("Discovering nearby travelers...")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .build()
        startForeground(NOTIFICATION_ID, notification)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onDestroy() {
        stopMesh()
        scope.cancel()
        super.onDestroy()
    }

    @SuppressLint("MissingPermission")
    fun startMesh(profileJson: String) {
        Log.d("LiitaBLE", "[LiitaBLE] startMesh() entered")

        val hasPerms = try { hasPermissions() } catch(e: Exception) { false }
        val isBtEnabled = try { bluetoothAdapter?.isEnabled } catch (e: Exception) { false }
        Log.d("LiitaBLE", "[LiitaBLE] hasPermissions=$hasPerms, bluetoothAdapter.isEnabled=$isBtEnabled")

        if (!hasPermissions() || bluetoothAdapter?.isEnabled != true) return
        if (isRunning) return

        try {
            val profile = JSONObject(profileJson)
            localDeviceId = profile.getString("deviceId")
            localProfileJson = profileJson

            relayController = RelayController(localDeviceId, dedupCache, scope) { packet ->
                relayPacket(packet)
            }

            bluetoothLeAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
            bluetoothLeScanner = bluetoothAdapter?.bluetoothLeScanner

            startGattServer()
            startAdvertising(profile)
            isRunning = true
            setContinuousMode() // Default to continuous scanning when started
        } catch (e: Exception) {
            Log.e(TAG, "Error starting mesh", e)
        }
    }

    @SuppressLint("MissingPermission")
    fun stopMesh() {
        if (!hasPermissions() || !isRunning) return

        dutyCycleJob?.cancel()
        bluetoothLeScanner?.stopScan(scanCallback)
        bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
        gattServer?.close()
        peerRegistry.clear()
        dedupCache.clear()
        connectingDevices.clear()
        writeQueue.clear()
        isWriting = false

        isRunning = false
    }

    // -------------------------------------------------------------------------
    // GATT Server (Receiving writes from others)
    // -------------------------------------------------------------------------

    @SuppressLint("MissingPermission")
    private fun startGattServer() {
        gattServer = bluetoothManager?.openGattServer(this, gattServerCallback)

        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        val char = BluetoothGattCharacteristic(
            PROFILE_CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
            BluetoothGattCharacteristic.PERMISSION_READ or BluetoothGattCharacteristic.PERMISSION_WRITE
        )
        service.addCharacteristic(char)
        gattServer?.addService(service)
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            // We only care about connections when acting as client, but can track here if needed
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic
        ) {
            if (characteristic.uuid == PROFILE_CHAR_UUID && hasPermissions()) {
                val value = localProfileJson.toByteArray(Charsets.UTF_8)
                val sliced = if (offset < value.size) value.copyOfRange(offset, value.size) else ByteArray(0)
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, sliced)
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            if (characteristic.uuid == PROFILE_CHAR_UUID && value != null) {
                if (responseNeeded && hasPermissions()) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
                }

                // Handle incoming packet
                handleIncomingGattWrite(value)
            }
        }
    }

    private fun handleIncomingGattWrite(value: ByteArray) {
        val base64Str = String(value, Charsets.UTF_8)
        val jsonStr = Utils.decodeAndDecompress(base64Str) ?: return

        val packet = MeshPacket.fromJson(jsonStr) ?: return

        // Rule 1: Dedup cache check
        val degree = dedupCache.recordAndGetDegree(packet.packetId)
        if (degree > 1) {
            Log.d("LiitaBLE", "[LiitaBLE] packet dropped (dedup): id=${packet.packetId}")
            return
        }

        // Rule 3/4: Consume if destination matches or is broadcast
        if (packet.destinationId == localDeviceId || packet.isBroadcast) {
            onPacketReceived?.invoke(jsonStr)
        }

        // Forward to relay controller for TTL/Jitter logic — but NOT unicast packets addressed to us
        if (packet.destinationId != localDeviceId) {
            Log.d("LiitaBLE", "[LiitaBLE] packet relayed: id=${packet.packetId}")
            relayController.processForRelay(packet)
        }
    }

    // -------------------------------------------------------------------------
    // Outbound (Relaying & Sending) — Bug 6 fix: serial write queue
    // -------------------------------------------------------------------------

    fun sendPacketFromDart(jsonStr: String) {
        val packet = MeshPacket.fromJson(jsonStr) ?: return

        // Add to our own dedup cache so we don't echo it if we hear it back
        dedupCache.recordAndGetDegree(packet.packetId)

        relayPacket(packet)
    }

    @SuppressLint("MissingPermission")
    private fun relayPacket(packet: MeshPacket) {
        if (!hasPermissions()) return

        val jsonStr = packet.toJson()
        val payloadStr = Utils.compressAndEncode(jsonStr)
        val payloadBytes = payloadStr.toByteArray(Charsets.UTF_8)

        val connections = peerRegistry.getAllConnections()
        for (gatt in connections) {
            val service = gatt.getService(SERVICE_UUID)
            val char = service?.getCharacteristic(PROFILE_CHAR_UUID)
            if (char != null) {
                writeQueue.add(WriteRequest(gatt, payloadBytes))
                Log.d("LiitaBLE", "[LiitaBLE] write queued for ${gatt.device.address}, queue size=${writeQueue.size}")
            }
        }
        drainWriteQueue()
    }

    @SuppressLint("MissingPermission")
    private fun drainWriteQueue() {
        if (isWriting) return
        val request = writeQueue.poll() ?: return
        isWriting = true

        mainHandler.post {
            try {
                val service = request.gatt.getService(SERVICE_UUID)
                val char = service?.getCharacteristic(PROFILE_CHAR_UUID)
                if (char != null && hasPermissions()) {
                    char.value = request.payload
                    char.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                    val success = request.gatt.writeCharacteristic(char)
                    Log.d("LiitaBLE", "[LiitaBLE] write dispatched to ${request.gatt.device.address}, success=$success")
                    if (!success) {
                        // Write failed immediately — advance to next
                        Log.e("LiitaBLE", "[LiitaBLE] writeCharacteristic returned false for ${request.gatt.device.address}")
                        isWriting = false
                        drainWriteQueue()
                    }
                    // On success, onCharacteristicWrite callback will call drainWriteQueue
                } else {
                    Log.e("LiitaBLE", "[LiitaBLE] write skipped — service/char null for ${request.gatt.device.address}")
                    isWriting = false
                    drainWriteQueue()
                }
            } catch (e: Exception) {
                Log.e("LiitaBLE", "[LiitaBLE] write exception for ${request.gatt.device.address}", e)
                isWriting = false
                drainWriteQueue()
            }
        }
    }

    // -------------------------------------------------------------------------
    // Advertising — Bug 1 fix: keep primary AD under 31 bytes
    // -------------------------------------------------------------------------

    @SuppressLint("MissingPermission")
    private fun startAdvertising(profile: JSONObject) {
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()

        // Primary AdvertisementData: 31 bytes max.
        // Flags (3) + 128-bit UUID (16+2) = 21 bytes. Leaves 10 bytes — not enough for
        // manufacturer data header (4) + 8 byte shortId. So keep the primary AD lean.
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()

        // ScanResponseData (separate 31-byte budget):
        // ManufacturerData 0xFFFE: shortId(8) = 8+4 = 12 bytes
        // ManufacturerData 0xFFFF: name(12)+age(1)+seat(4)+version(1) = 18+4 = 22 bytes
        // Total: 34 bytes — exceeds 31. So we pack shortId into 0xFFFE and profile
        // into a reduced-size block under 0xFFFF.
        //
        // Revised layout — single manufacturer data block in scan response:
        // shortId(8) + name(8) + age(1) + seat(4) + version(1) = 22 bytes + 4 header = 26 bytes.
        val deviceIdRaw = profile.getString("deviceId")
        val shortId = deviceIdRaw.take(8).toByteArray(Charsets.UTF_8)
        val name = profile.getString("name").take(8)
        val age = profile.getInt("age").toByte()
        val seat = profile.getString("seatNumber").take(4)
        val version = profile.getInt("version").toByte()

        // 22 bytes: shortId(8) + name(8) + age(1) + seat(4) + version(1)
        val scanRespBytes = ByteArray(22)
        System.arraycopy(shortId, 0, scanRespBytes, 0, shortId.size)
        val nameBytes = name.toByteArray(Charsets.UTF_8)
        System.arraycopy(nameBytes, 0, scanRespBytes, 8, nameBytes.size)
        scanRespBytes[16] = age
        val seatBytes = seat.toByteArray(Charsets.UTF_8)
        System.arraycopy(seatBytes, 0, scanRespBytes, 17, seatBytes.size)
        scanRespBytes[21] = version

        val scanResponse = AdvertiseData.Builder()
            .addManufacturerData(0xFFFF, scanRespBytes)
            .build()

        Log.d("LiitaBLE", "[LiitaBLE] startAdvertising: shortId=${deviceIdRaw.take(8)}, name=$name, scanRespBytes=${scanRespBytes.size}")
        bluetoothLeAdvertiser?.startAdvertising(settings, data, scanResponse, advertiseCallback)
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            Log.d("LiitaBLE", "[LiitaBLE] advertising started success")
        }
        override fun onStartFailure(errorCode: Int) {
            Log.e("LiitaBLE", "[LiitaBLE] advertiser start failure: errorCode=$errorCode")
        }
    }

    // -------------------------------------------------------------------------
    // Scanning & Duty Cycling
    // -------------------------------------------------------------------------

    fun setContinuousMode() {
        currentMode = 0
        applyDutyCycle()
    }

    fun setForegroundMode() {
        currentMode = 1
        applyDutyCycle()
    }

    fun setBackgroundMode() {
        currentMode = 2
        applyDutyCycle()
    }

    private var lastScanStartTime = 0L

    @SuppressLint("MissingPermission")
    private fun applyDutyCycle() {
        dutyCycleJob?.cancel()
        if (!isRunning || !hasPermissions()) return

        dutyCycleJob = scope.launch {
            // Jitter to prevent two devices syncing to opposite duty cycles
            delay((0..3000).random().toLong())

            while (isActive) {
                when (currentMode) {
                    0 -> { // Continuous
                        startScanning(ScanSettings.SCAN_MODE_LOW_LATENCY)
                        delay(Long.MAX_VALUE)
                    }
                    1 -> { // Foreground: 5s ON, 10s OFF
                        startScanning(ScanSettings.SCAN_MODE_LOW_LATENCY)
                        delay(5000)
                        stopScanning()
                        delay(10000)
                    }
                    2 -> { // Background: 3s ON, 20s OFF
                        startScanning(ScanSettings.SCAN_MODE_BALANCED)
                        delay(3000)
                        stopScanning()
                        delay(20000)
                    }
                }
            }
        }
    }

    @SuppressLint("MissingPermission")
    private suspend fun startScanning(mode: Int) {
        val now = System.currentTimeMillis()
        val elapsed = now - lastScanStartTime
        if (elapsed < 6500) {
            delay(6500 - elapsed)
        }
        lastScanStartTime = System.currentTimeMillis()

        val filters = listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE_UUID)).build())
        val settings = ScanSettings.Builder().setScanMode(mode).build()
        withContext(Dispatchers.Main) {
            bluetoothLeScanner?.startScan(filters, settings, scanCallback)
        }
        Log.d("LiitaBLE", "[LiitaBLE] scan started, mode=$mode")
    }

    @SuppressLint("MissingPermission")
    private fun stopScanning() {
        mainHandler.post {
            bluetoothLeScanner?.stopScan(scanCallback)
        }
    }

    // Bug 2 fix: resume scanning after a connect attempt completes
    private fun resumeScanningAfterConnect() {
        if (!isRunning || !hasPermissions()) return
        // Re-apply duty cycle which will restart scanning per the current mode
        Log.d("LiitaBLE", "[LiitaBLE] resuming scan after connect")
        applyDutyCycle()
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanFailed(errorCode: Int) {
            Log.e("LiitaBLE", "[LiitaBLE] scan failure: errorCode=$errorCode")
        }

        @SuppressLint("MissingPermission")
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            if (!hasPermissions()) return
            val device = result.device
            val address = device.address

            val uuids = result.scanRecord?.serviceUuids?.joinToString { it.uuid.toString() } ?: "none"
            Log.d("LiitaBLE", "[LiitaBLE] scan callback hit: device=$address, uuids=$uuids")

            // Bug 3 fix: skip if already connecting or already connected
            if (connectingDevices.containsKey(address)) {
                Log.d("LiitaBLE", "[LiitaBLE] skipping $address — already connecting")
            } else if (peerRegistry.getAllConnections().any { it.device.address == address }) {
                Log.d("LiitaBLE", "[LiitaBLE] skipping $address — already connected")
            } else {
                // Mark as connecting before stopping scan
                connectingDevices[address] = true
                Log.d("LiitaBLE", "[LiitaBLE] GATT connect attempt: device=$address")

                // Connect on main thread
                mainHandler.post {
                    if (hasPermissions()) {
                        device.connectGatt(this@MeshForegroundService, false, gattClientCallback)
                    }
                }
            }

            // Scan response data used only for logging — full profile comes from GATT read
            val scanRespData = result.scanRecord?.getManufacturerSpecificData(0xFFFF)
            Log.d("LiitaBLE", "[LiitaBLE] scan response for $address: ${scanRespData?.size ?: 0} bytes (full profile via GATT read)")
        }
    }

    private val gattClientCallback = object : BluetoothGattCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            val address = gatt.device.address
            Log.d("LiitaBLE", "[LiitaBLE] onConnectionStateChange: device=$address, status=$status, newState=$newState")

            if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                // Bug 3: remove from connecting set
                connectingDevices.remove(address)
                peerRegistry.addConnection(gatt)
                Log.d("LiitaBLE", "[LiitaBLE] connected to $address, discovering services")
                if (hasPermissions()) {
                    gatt.discoverServices()
                }
                // Bug 2: resume scanning since we stopped it before connect
                resumeScanningAfterConnect()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                // Bug 3: remove from connecting set
                connectingDevices.remove(address)
                peerRegistry.removeConnection(address)
                // Bug 5: explicitly close to free GATT client slot
                Log.d("LiitaBLE", "[LiitaBLE] disconnected from $address (status=$status), closing GATT")
                try {
                    gatt.close()
                } catch (e: Exception) {
                    Log.e("LiitaBLE", "[LiitaBLE] error closing GATT for $address", e)
                }
                // Bug 2: resume scanning on disconnect too
                resumeScanningAfterConnect()
            } else {
                // Connection failed (e.g. status 133)
                connectingDevices.remove(address)
                Log.e("LiitaBLE", "[LiitaBLE] connection failed for $address, status=$status, closing GATT")
                try {
                    gatt.close()
                } catch (e: Exception) {
                    Log.e("LiitaBLE", "[LiitaBLE] error closing GATT for $address", e)
                }
                resumeScanningAfterConnect()
            }
        }

        @SuppressLint("MissingPermission")
        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            val address = gatt.device.address
            if (status == BluetoothGatt.GATT_SUCCESS && hasPermissions()) {
                Log.d("LiitaBLE", "[LiitaBLE] services discovered for $address, reading profile characteristic")
                val service = gatt.getService(SERVICE_UUID)
                val char = service?.getCharacteristic(PROFILE_CHAR_UUID)
                if (char != null) {
                    gatt.readCharacteristic(char)
                } else {
                    Log.e("LiitaBLE", "[LiitaBLE] profile characteristic not found on $address")
                }
            } else {
                Log.e("LiitaBLE", "[LiitaBLE] service discovery failed for $address, status=$status")
            }
        }

        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int
        ) {
            val address = gatt.device.address
            if (status == BluetoothGatt.GATT_SUCCESS && characteristic.uuid == PROFILE_CHAR_UUID) {
                val value = characteristic.value ?: return
                val profileJson = String(value, Charsets.UTF_8)
                Log.d("LiitaBLE", "[LiitaBLE] characteristic read from $address: ${profileJson.take(80)}...")
                if (peerRegistry.updatePeerProfile(address, profileJson)) {
                    val deviceId = try { JSONObject(profileJson).getString("deviceId") } catch (e: Exception) { address }
                    Log.d("LiitaBLE", "[LiitaBLE] peer discovered via GATT read: $deviceId")
                    onPeerDiscovered?.invoke(profileJson)
                }
                // Disconnect to free GATT slot (Android limit ~7 concurrent)
                Log.d("LiitaBLE", "[LiitaBLE] disconnecting from $address after profile read")
                if (hasPermissions()) gatt.disconnect()
            } else {
                Log.e("LiitaBLE", "[LiitaBLE] characteristic read failed for $address, status=$status")
            }
        }

        // Bug 6 fix: advance write queue after each completed write
        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int
        ) {
            val address = gatt.device.address
            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.d("LiitaBLE", "[LiitaBLE] write completed for $address")
            } else {
                Log.e("LiitaBLE", "[LiitaBLE] write failed for $address, status=$status")
            }
            isWriting = false
            drainWriteQueue()
        }
    }

    // -------------------------------------------------------------------------
    // Utilities
    // -------------------------------------------------------------------------

    private fun hasPermissions(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED &&
                   ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED &&
                   ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED
        }
        return ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Liita Mesh Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps BLE mesh networking active"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }
}
