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
import java.util.concurrent.atomic.AtomicReference

class MeshForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "liita_mesh_channel"
        const val NOTIFICATION_ID = 1
        val SERVICE_UUID: UUID = UUID.fromString("6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
        val PROFILE_CHAR_UUID: UUID = UUID.fromString("6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
        const val TAG = "MeshForegroundService"
        // RC-1: Minimum MTU we negotiate. 247 gives 244-byte writes (max for BLE 4.2/5.0).
        const val TARGET_MTU = 247
        // Safety timeout for each send task — prevents isSending deadlock if connectGatt hangs.
        const val SEND_TIMEOUT_MS = 8000L
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
    // Value is the Job for the hang-timeout so we can cancel it on success.
    private val connectingDevices = ConcurrentHashMap<String, Job>()

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
        sendJob?.cancel()   // RC-3: Stop any in-flight send job
        bluetoothLeScanner?.stopScan(scanCallback)
        bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
        gattServer?.close()
        peerRegistry.clear()
        dedupCache.clear()
        connectingDevices.values.forEach { it.cancel() }  // FIX 1B: cancel pending hang-timeout jobs
        connectingDevices.clear()
        pendingSendGatt.getAndSet(null)?.let { g ->        // FIX 2A: close any in-flight send GATT
            try { g.disconnect() } catch (_: Exception) {}
            try { g.close() } catch (_: Exception) {}
        }
        writeQueue.clear()
        isWriting = false
        sendQueue.clear()   // RC-3: Drain send queue on stop

        isRunning = false
    }

    // -------------------------------------------------------------------------
    // RC-3 / RC-4: Serialized outbound send queue
    //
    // Instead of spawning a connectGatt for every peer simultaneously,
    // we queue (device, payload) pairs and process them one at a time,
    // fully chaining: connect → discoverServices → requestMtu →
    // onMtuChanged → writeCharacteristic → onCharacteristicWrite → disconnect → close.
    // -------------------------------------------------------------------------

    private data class SendTask(val device: BluetoothDevice, val payloadBytes: ByteArray)
    private val sendQueue = ConcurrentLinkedQueue<SendTask>()
    @Volatile private var isSending = false
    private var sendJob: Job? = null
    // FIX 2A/2B: Store GATT ref so the timeout coroutine can close it
    private val pendingSendGatt = AtomicReference<BluetoothGatt?>(null)

    @SuppressLint("MissingPermission")
    private fun enqueueSend(device: BluetoothDevice, payloadBytes: ByteArray) {
        sendQueue.add(SendTask(device, payloadBytes.copyOf()))
        drainSendQueue()
    }

    @SuppressLint("MissingPermission")
    private fun drainSendQueue() {
        if (isSending) return
        val task = sendQueue.poll() ?: return
        if (!hasPermissions() || !isRunning) return
        isSending = true
        pendingSendGatt.set(null)

        Log.d(TAG, "[LiitaBLE] drainSendQueue: connecting to ${task.device.address}")

        // FIX 2A/2B: Safety timeout now also closes the hung GATT client so no slot is leaked.
        sendJob?.cancel()
        sendJob = scope.launch {
            delay(SEND_TIMEOUT_MS)
            if (isSending) {
                Log.e(TAG, "[LiitaBLE] send timeout for ${task.device.address} — closing GATT and force-draining")
                // Close the hung GATT to release the clientif slot
                pendingSendGatt.getAndSet(null)?.let { g ->
                    try { g.disconnect() } catch (_: Exception) {}
                    try { g.close() } catch (_: Exception) {}
                }
                isSending = false
                mainHandler.post { drainSendQueue() }
            }
        }

        mainHandler.post {
            if (hasPermissions()) {
                val gatt = task.device.connectGatt(this, false, buildSendCallback(task), BluetoothDevice.TRANSPORT_LE)
                pendingSendGatt.set(gatt)
            } else {
                sendJob?.cancel()
                isSending = false
                drainSendQueue()
            }
        }
    }

    // RC-1 / RC-2: One callback instance per send task. Chains MTU → write → disconnect → close.
    @SuppressLint("MissingPermission")
    private fun buildSendCallback(task: SendTask): BluetoothGattCallback {
        return object : BluetoothGattCallback() {
            private var servicesDiscovered = false
            private var mtuNegotiated = false
            private var payloadWritten = false

            private fun tryWrite(gatt: BluetoothGatt) {
                if (servicesDiscovered && mtuNegotiated && !payloadWritten) {
                    payloadWritten = true
                    writePayload(gatt)
                }
            }

            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                    Log.d(TAG, "[LiitaBLE] send-connect ok to ${task.device.address}, discovering services")
                    if (hasPermissions()) gatt.discoverServices()
                    else finishSend(gatt)
                } else {
                    Log.w(TAG, "[LiitaBLE] send-connect failed to ${task.device.address}: status=$status")
                    finishSend(gatt)
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS && hasPermissions()) {
                    servicesDiscovered = true
                    // RC-1: Request MTU BEFORE writing.
                    val requested = gatt.requestMtu(TARGET_MTU)
                    Log.d(TAG, "[LiitaBLE] requestMtu($TARGET_MTU) for ${task.device.address}: dispatched=$requested")
                    if (!requested) {
                        Log.w(TAG, "[LiitaBLE] requestMtu returned false, proceeding to write")
                        mtuNegotiated = true
                        tryWrite(gatt)
                    }
                } else {
                    Log.w(TAG, "[LiitaBLE] service discovery failed for ${task.device.address}: status=$status")
                    finishSend(gatt)
                }
            }

            override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
                Log.d(TAG, "[LiitaBLE] onMtuChanged for ${task.device.address}: mtu=$mtu status=$status")
                mtuNegotiated = true
                tryWrite(gatt)
            }

            private fun writePayload(gatt: BluetoothGatt) {
                val service = gatt.getService(SERVICE_UUID)
                val char = service?.getCharacteristic(PROFILE_CHAR_UUID)
                if (char != null && hasPermissions()) {
                    char.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                    char.value = task.payloadBytes
                    val ok = gatt.writeCharacteristic(char)
                    Log.d(TAG, "[LiitaBLE] writeCharacteristic to ${task.device.address}: ok=$ok payload=${task.payloadBytes.size}B")
                    if (!ok) finishSend(gatt)
                } else {
                    Log.w(TAG, "[LiitaBLE] service/char null on ${task.device.address}, skipping send")
                    finishSend(gatt)
                }
            }

            override fun onCharacteristicWrite(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
                Log.d(TAG, "[LiitaBLE] write complete to ${task.device.address}: status=$status")
                finishSend(gatt)
            }

            private fun finishSend(gatt: BluetoothGatt) {
                try {
                    if (hasPermissions()) gatt.disconnect()
                    gatt.close()
                } catch (e: Exception) {
                    Log.e(TAG, "[LiitaBLE] finishSend close error: ${e.message}")
                }
                sendJob?.cancel()  // Cancel the safety timeout — send completed normally
                isSending = false
                drainSendQueue()  // Process the next task in the queue
            }
        }
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
        val jsonStr = Utils.decodeAndDecompress(base64Str) ?: run {
            Log.e(TAG, "[LiitaBLE] handleIncomingGattWrite: Base64/GZip decode failed. " +
                "Received ${value.size} bytes. Likely MTU truncation — check that sender negotiated MTU.")
            return
        }
        val packet = MeshPacket.fromJson(jsonStr) ?: run {
            Log.e(TAG, "[LiitaBLE] handleIncomingGattWrite: MeshPacket JSON parse failed. raw=$jsonStr")
            return
        }

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

        // FIX 2D: Unicast packets go to one device only; only broadcasts fan out to all.
        if (!packet.isBroadcast && packet.destinationId.isNotEmpty()) {
            val target = peerRegistry.getDeviceById(packet.destinationId)
            if (target != null) {
                enqueueSend(target, payloadBytes)
            } else {
                Log.w(TAG, "[LiitaBLE] relayPacket: unicast target ${packet.destinationId.take(8)} not in registry — broadcasting as fallback")
                for (device in peerRegistry.getAllKnownDevices()) { enqueueSend(device, payloadBytes) }
            }
        } else {
            for (device in peerRegistry.getAllKnownDevices()) { enqueueSend(device, payloadBytes) }
        }
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
        // FIX 1C: Truncate by bytes, not characters, to prevent UTF-8 overflow.
        fun String.truncateToBytes(maxBytes: Int): ByteArray {
            val full = this.toByteArray(Charsets.UTF_8)
            return if (full.size <= maxBytes) full else full.copyOf(maxBytes)
        }
        val shortId  = deviceIdRaw.truncateToBytes(8)   // slot [0..7]
        val nameBytes = profile.getString("name").truncateToBytes(8)  // slot [8..15]
        val age      = profile.getInt("age").toByte()                  // slot [16]
        val seatBytes = profile.getString("seatNumber").truncateToBytes(4) // slot [17..20]
        val version  = profile.getInt("version").toByte()              // slot [21]

        // 22 bytes: shortId(8) + name(8) + age(1) + seat(4) + version(1)
        val scanRespBytes = ByteArray(22)
        System.arraycopy(shortId, 0, scanRespBytes, 0, shortId.size)
        System.arraycopy(nameBytes, 0, scanRespBytes, 8, nameBytes.size)
        scanRespBytes[16] = age
        System.arraycopy(seatBytes, 0, scanRespBytes, 17, seatBytes.size)
        scanRespBytes[21] = version

        val scanResponse = AdvertiseData.Builder()
            .addManufacturerData(0xFFFF, scanRespBytes)
            .build()

        Log.d("LiitaBLE", "[LiitaBLE] startAdvertising: shortId=${deviceIdRaw.take(8)}, name=${String(nameBytes)}, scanRespBytes=${scanRespBytes.size}")
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

    // FIX 1A: Resume scanning WITHOUT restarting the duty-cycle loop.
    // Calling applyDutyCycle() here was creating a new startScan() on every connect/disconnect,
    // easily tripping Android's hidden 5-scans-in-30s quota.
    private fun resumeScanningAfterConnect() {
        if (!isRunning || !hasPermissions()) return
        // Only restart if the duty cycle job has died (e.g. first startup).
        // Normal operation: the loop is already running; don't touch it.
        if (dutyCycleJob == null || dutyCycleJob?.isActive == false) {
            Log.d("LiitaBLE", "[LiitaBLE] duty cycle was dead — restarting after connect")
            applyDutyCycle()
        } else {
            Log.d("LiitaBLE", "[LiitaBLE] resuming scan after connect (duty cycle already active, no restart)")
        }
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
            peerRegistry.addKnownDevice(device)

            val uuids = result.scanRecord?.serviceUuids?.joinToString { it.uuid.toString() } ?: "none"
            Log.d("LiitaBLE", "[LiitaBLE] scan callback hit: device=$address, uuids=$uuids")

            // Bug 3 fix: skip if already connecting or already connected
            if (connectingDevices.containsKey(address)) {
                Log.d("LiitaBLE", "[LiitaBLE] skipping $address — already connecting")
            } else if (peerRegistry.getAllConnections().any { it.device.address == address }) {
                Log.d("LiitaBLE", "[LiitaBLE] skipping $address — already connected")
            } else {
                Log.d("LiitaBLE", "[LiitaBLE] GATT connect attempt: device=$address")

                // FIX 1B: Store a timeout Job in connectingDevices. If connectGatt never fires
                // onConnectionStateChange (Android bug), we remove the address ourselves after
                // 10s so it can be retried on the next scan hit.
                val hangTimeout = scope.launch {
                    delay(10_000L)
                    if (connectingDevices.containsKey(address)) {
                        Log.w(TAG, "[LiitaBLE] connectGatt hang timeout for $address — clearing connectingDevices entry")
                        connectingDevices.remove(address)
                        // We have no gatt reference here (connectGatt returned on main thread),
                        // so we cannot close it — but the slot will eventually be reclaimed by Android.
                    }
                }
                connectingDevices[address] = hangTimeout

                // Connect on main thread
                mainHandler.post {
                    if (hasPermissions()) {
                        device.connectGatt(this@MeshForegroundService, false, gattClientCallback)
                    } else {
                        hangTimeout.cancel()
                        connectingDevices.remove(address)
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
                // FIX 1B: cancel the hang-timeout job and remove from connecting set
                connectingDevices.remove(address)?.cancel()
                peerRegistry.addConnection(gatt)
                Log.d("LiitaBLE", "[LiitaBLE] connected to $address, discovering services")
                if (hasPermissions()) {
                    gatt.discoverServices()
                }
                resumeScanningAfterConnect()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                // FIX 1B: cancel the hang-timeout job and remove from connecting set
                connectingDevices.remove(address)?.cancel()
                peerRegistry.removeConnection(address)
                Log.d("LiitaBLE", "[LiitaBLE] disconnected from $address (status=$status), closing GATT")
                try {
                    gatt.close()
                } catch (e: Exception) {
                    Log.e("LiitaBLE", "[LiitaBLE] error closing GATT for $address", e)
                }
                resumeScanningAfterConnect()
            } else {
                // Connection failed (e.g. status 133)
                // FIX 1B: cancel the hang-timeout job and remove from connecting set
                connectingDevices.remove(address)?.cancel()
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
