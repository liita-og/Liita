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
import android.os.IBinder
import android.os.ParcelUuid
import android.util.Log
import androidx.core.app.ActivityCompat
import kotlinx.coroutines.*
import org.json.JSONObject
import java.util.UUID

class MeshForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "liita_mesh_channel"
        const val NOTIFICATION_ID = 1
        val SERVICE_UUID: UUID = UUID.fromString("6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
        val PROFILE_CHAR_UUID: UUID = UUID.fromString("6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
        const val TAG = "MeshForegroundService"
    }

    private val binder = LocalBinder()
    
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
            setContinuousMode() // Default to continuous scanning when started
            isRunning = true
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
            // It's a duplicate. Bitchat degree tracking allows RelayController to know it's a dupe.
            // But we don't process it further here.
            return
        }
        
        // Rule 3/4: Consume if destination matches or is broadcast
        if (packet.destinationId == localDeviceId || packet.isBroadcast) {
            onPacketReceived?.invoke(jsonStr)
        }
        
        // Forward to relay controller for TTL/Jitter logic
        relayController.processForRelay(packet)
    }

    // -------------------------------------------------------------------------
    // Outbound (Relaying & Sending)
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
                char.value = payloadBytes
                char.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                gatt.writeCharacteristic(char)
            }
        }
    }

    // -------------------------------------------------------------------------
    // Advertising
    // -------------------------------------------------------------------------

    @SuppressLint("MissingPermission")
    private fun startAdvertising(profile: JSONObject) {
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()
            
        // AdvertisementData: 31 bytes max.
        // Flags (3) + UUID (18) = 21 bytes. Leaves 10 bytes.
        // We pack the 8-char deviceId prefix.
        val deviceIdRaw = profile.getString("deviceId")
        val shortId = deviceIdRaw.take(8).toByteArray(Charsets.UTF_8)
        
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .addServiceData(ParcelUuid(SERVICE_UUID), shortId)
            .build()
            
        // ScanResponseData: pack name(20), age(1), seat(4), version(1)
        val name = profile.getString("name").take(20)
        val age = profile.getInt("age").toByte()
        val seat = profile.getString("seatNumber").take(4)
        val version = profile.getInt("version").toByte()
        
        val scanRespBytes = ByteArray(26)
        val nameBytes = name.toByteArray(Charsets.UTF_8)
        System.arraycopy(nameBytes, 0, scanRespBytes, 0, nameBytes.size)
        scanRespBytes[20] = age
        val seatBytes = seat.toByteArray(Charsets.UTF_8)
        System.arraycopy(seatBytes, 0, scanRespBytes, 21, seatBytes.size)
        scanRespBytes[25] = version

        val scanResponse = AdvertiseData.Builder()
            .addServiceData(ParcelUuid(PROFILE_CHAR_UUID), scanRespBytes)
            .build()

        bluetoothLeAdvertiser?.startAdvertising(settings, data, scanResponse, advertiseCallback)
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            Log.d("LiitaBLE", "[LiitaBLE] advertising started")
        }
        override fun onStartFailure(errorCode: Int) {
            Log.e(TAG, "Advertising failed: $errorCode")
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

    @SuppressLint("MissingPermission")
    private fun applyDutyCycle() {
        dutyCycleJob?.cancel()
        if (!isRunning || !hasPermissions()) return
        
        dutyCycleJob = scope.launch {
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
    private fun startScanning(mode: Int) {
        val filters = listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE_UUID)).build())
        val settings = ScanSettings.Builder().setScanMode(mode).build()
        bluetoothLeScanner?.startScan(filters, settings, scanCallback)
    }

    @SuppressLint("MissingPermission")
    private fun stopScanning() {
        bluetoothLeScanner?.stopScan(scanCallback)
    }

    private val scanCallback = object : ScanCallback() {
        @SuppressLint("MissingPermission")
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            if (!hasPermissions()) return
            val device = result.device
            
            // Connect to discovered device so we can write MeshPackets to it later
            if (peerRegistry.getAllConnections().none { it.device.address == device.address }) {
                // Sequential pattern: Stop scan before connect on Android to prevent 133 error
                stopScanning()
                device.connectGatt(this@MeshForegroundService, false, gattClientCallback)
                // Resume scan will happen in duty cycle loop or we can force it
            }
            
            // Reconstruct partial profile from scan response
            val scanRespData = result.scanRecord?.getServiceData(ParcelUuid(PROFILE_CHAR_UUID))
            val shortIdData = result.scanRecord?.getServiceData(ParcelUuid(SERVICE_UUID))
            if (scanRespData != null && shortIdData != null && scanRespData.size >= 26) {
                try {
                    val nameStr = String(scanRespData, 0, 20, Charsets.UTF_8).trimEnd('\u0000')
                    val age = scanRespData[20].toInt()
                    val seatStr = String(scanRespData, 21, 4, Charsets.UTF_8).trimEnd('\u0000')
                    val version = scanRespData[25].toInt()
                    
                    // We only have the 8-char short ID here. 
                    // But we must construct a JSON for the Flutter layer.
                    // Ideally the Flutter layer reads the full profile via a 'p' packet.
                    // For now, emit a partial.
                    val partialJson = JSONObject().apply {
                        put("deviceId", String(shortIdData, Charsets.UTF_8))
                        put("name", nameStr)
                        put("age", age)
                        put("seatNumber", seatStr)
                        put("version", version)
                        put("publicKey", "")
                        put("occupation", "")
                    }.toString()
                    
                    if (peerRegistry.updatePeerProfile(device.address, partialJson)) {
                        Log.d("LiitaBLE", "[LiitaBLE] peer discovered: ${String(shortIdData, Charsets.UTF_8)}")
                        onPeerDiscovered?.invoke(partialJson)
                    }
                } catch (e: Exception) {}
            }
        }
    }

    private val gattClientCallback = object : BluetoothGattCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                peerRegistry.addConnection(gatt)
                if (hasPermissions()) {
                    gatt.discoverServices()
                }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                peerRegistry.removeConnection(gatt.device.address)
                if (hasPermissions()) {
                    gatt.close()
                }
            }
        }
        
        @SuppressLint("MissingPermission")
        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS && hasPermissions()) {
                // Request higher MTU for relaying packets
                gatt.requestMtu(512)
                
                // Read full profile
                val service = gatt.getService(SERVICE_UUID)
                val char = service?.getCharacteristic(PROFILE_CHAR_UUID)
                if (char != null) {
                    gatt.readCharacteristic(char)
                }
            }
        }

        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int
        ) {
            if (status == BluetoothGatt.GATT_SUCCESS && characteristic.uuid == PROFILE_CHAR_UUID) {
                val value = characteristic.value ?: return
                val profileJson = String(value, Charsets.UTF_8)
                if (peerRegistry.updatePeerProfile(gatt.device.address, profileJson)) {
                    val deviceId = try { JSONObject(profileJson).getString("deviceId") } catch (e: Exception) { gatt.device.address }
                    Log.d("LiitaBLE", "[LiitaBLE] peer discovered: $deviceId")
                    onPeerDiscovered?.invoke(profileJson)
                }
            }
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
