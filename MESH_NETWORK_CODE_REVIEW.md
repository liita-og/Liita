# Liita BLE Mesh Network — Full Source Code for Review

> **Generated:** 2026-06-04  
> **BLE Service UUID:** `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`  
> **Profile Characteristic UUID:** `6E400002-B5A3-F393-E0A9-E50E24DCCA9E`

---

## Table of Contents

1. [Kotlin — MeshForegroundService.kt](#1-meshforegroundservicekt) (BLE core: advertising, scanning, GATT, relay)
2. [Kotlin — MeshPlugin.kt](#2-meshpluginkt) (Flutter ↔ Native bridge)
3. [Kotlin — MeshPacket.kt](#3-meshpacketkt) (Packet data class)
4. [Kotlin — RelayController.kt](#4-relaycontrollerkt) (TTL/jitter relay logic)
5. [Kotlin — DeduplicationCache.kt](#5-deduplicationcachekt) (Dedup cache)
6. [Kotlin — BlePeerRegistry.kt](#6-blepeerregistrykt) (Connected peer tracking)
7. [Kotlin — Utils.kt](#7-utilskt) (Gzip + Base64)
8. [Dart — mesh_service.dart](#8-mesh_servicedart) (Abstract interface)
9. [Dart — mesh_service_flutter.dart](#9-mesh_service_flutterdart) (Platform channel implementation)
10. [Dart — mesh_packet.dart](#10-mesh_packetdart) (Dart packet model)
11. [Dart — providers.dart](#11-providersdart) (Riverpod providers)
12. [Dart — radar_screen.dart](#12-radar_screendart) (Radar UI + wave button)
13. [Dart — main.dart](#13-maindart) (Boot sequence)
14. [Config — AndroidManifest.xml](#14-androidmanifestxml)

---

## 1. MeshForegroundService.kt

**Path:** `android/app/src/main/kotlin/com/liita/liita/MeshForegroundService.kt`

```kotlin
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
            Log.d("LiitaBLE", "[LiitaBLE] packet dropped (dedup): id=${packet.packetId}")
            return
        }
        
        // Rule 3/4: Consume if destination matches or is broadcast
        if (packet.destinationId == localDeviceId || packet.isBroadcast) {
            onPacketReceived?.invoke(jsonStr)
        }
        
        // Forward to relay controller for TTL/Jitter logic
        Log.d("LiitaBLE", "[LiitaBLE] packet relayed: id=${packet.packetId}")
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
        // Flags (3) + UUID (16+2) + ManufacturerData (2+8+2) = 31 bytes.
        val deviceIdRaw = profile.getString("deviceId")
        val shortId = deviceIdRaw.take(8).toByteArray(Charsets.UTF_8)
        
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .addManufacturerData(0xFFFE, shortId)
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
            .addManufacturerData(0xFFFF, scanRespBytes)
            .build()

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
        bluetoothLeScanner?.startScan(filters, settings, scanCallback)
    }

    @SuppressLint("MissingPermission")
    private fun stopScanning() {
        bluetoothLeScanner?.stopScan(scanCallback)
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanFailed(errorCode: Int) {
            Log.e("LiitaBLE", "[LiitaBLE] scan failure: errorCode=$errorCode")
        }

        @SuppressLint("MissingPermission")
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            if (!hasPermissions()) return
            val device = result.device
            
            val uuids = result.scanRecord?.serviceUuids?.joinToString { it.uuid.toString() } ?: "none"
            Log.d("LiitaBLE", "[LiitaBLE] scan callback hit: device=${device.address}, uuids=$uuids")
            
            // Connect to discovered device so we can write MeshPackets to it later
            if (peerRegistry.getAllConnections().none { it.device.address == device.address }) {
                // Sequential pattern: Stop scan before connect on Android to prevent 133 error
                Log.d("LiitaBLE", "[LiitaBLE] GATT connect attempt: device=${device.address}")
                stopScanning()
                device.connectGatt(this@MeshForegroundService, false, gattClientCallback)
                // Resume scan will happen in duty cycle loop or we can force it
            }
            
            // Reconstruct partial profile from scan response
            val scanRespData = result.scanRecord?.getManufacturerSpecificData(0xFFFF)
            val shortIdData = result.scanRecord?.getManufacturerSpecificData(0xFFFE)
            if (scanRespData != null && shortIdData != null && scanRespData.size >= 26) {
                try {
                    val nameStr = String(scanRespData, 0, 20, Charsets.UTF_8).trimEnd('\u0000')
                    val age = scanRespData[20].toInt() and 0xFF
                    val seatStr = String(scanRespData, 21, 4, Charsets.UTF_8).trimEnd('\u0000')
                    val version = scanRespData[25].toInt() and 0xFF
                    
                    val shortIdStr = String(shortIdData, Charsets.UTF_8)
                    
                    val partialJson = JSONObject().apply {
                        put("deviceId", shortIdStr)
                        put("name", nameStr)
                        put("age", age)
                        put("seatNumber", seatStr)
                        put("version", version)
                        put("publicKey", "")
                        put("occupation", "")
                    }.toString()
                    
                    if (peerRegistry.updatePeerProfile(device.address, partialJson)) {
                        Log.d("LiitaBLE", "[LiitaBLE] peer discovered: $shortIdStr")
                        onPeerDiscovered?.invoke(partialJson)
                    }
                } catch (e: Exception) {}
            } else {
                Log.d("LiitaBLE", "[LiitaBLE] scan filter miss: data missing or malformed for ${device.address}")
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
```

---

## 2. MeshPlugin.kt

**Path:** `android/app/src/main/kotlin/com/liita/liita/MeshPlugin.kt`

```kotlin
package com.liita.liita

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import android.util.Log

class MeshPlugin(private val context: Context, flutterEngine: FlutterEngine) : MethodCallHandler {
    companion object {
        const val TAG = "MeshPlugin"
    }

    private val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.liita.app/mesh")
    private val peersChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.liita.app/peers")
    private val packetsChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.liita.app/packets")

    private var meshService: MeshForegroundService? = null
    private var isBound = false

    private var peersSink: EventChannel.EventSink? = null
    private var packetsSink: EventChannel.EventSink? = null

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            val binder = service as MeshForegroundService.LocalBinder
            meshService = binder.getService()
            isBound = true
            setupServiceCallbacks()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            meshService = null
            isBound = false
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)

        peersChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                peersSink = events
            }
            override fun onCancel(arguments: Any?) {
                peersSink = null
            }
        })

        packetsChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                packetsSink = events
            }
            override fun onCancel(arguments: Any?) {
                packetsSink = null
            }
        })

        // Bind the service so it's ready, but don't start it as foreground until startMesh is called
        val intent = Intent(context, MeshForegroundService::class.java)
        context.bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
    }

    private fun setupServiceCallbacks() {
        meshService?.onPeerDiscovered = { profileJson ->
            peersSink?.success(profileJson)
        }
        meshService?.onPacketReceived = { packetJson ->
            packetsSink?.success(packetJson)
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startMesh" -> {
                val profileJson = call.argument<String>("profileJson")
                if (profileJson != null) {
                    val intent = Intent(context, MeshForegroundService::class.java)
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                    meshService?.startMesh(profileJson)
                    result.success(null)
                } else {
                    result.error("INVALID_ARG", "profileJson is required", null)
                }
            }
            "stopMesh" -> {
                meshService?.stopMesh()
                result.success(null)
            }
            "sendPacket" -> {
                val packetJson = call.argument<String>("packetJson")
                if (packetJson != null) {
                    meshService?.sendPacketFromDart(packetJson)
                    result.success(null)
                } else {
                    result.error("INVALID_ARG", "packetJson is required", null)
                }
            }
            "setForegroundMode" -> {
                meshService?.setForegroundMode()
                result.success(null)
            }
            "setBackgroundMode" -> {
                meshService?.setBackgroundMode()
                result.success(null)
            }
            "setContinuousMode" -> {
                meshService?.setContinuousMode()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun destroy() {
        if (isBound) {
            context.unbindService(serviceConnection)
            isBound = false
        }
    }
}
```

---

## 3. MeshPacket.kt

**Path:** `android/app/src/main/kotlin/com/liita/liita/MeshPacket.kt`

```kotlin
package com.liita.liita

import org.json.JSONObject

data class MeshPacket(
    val packetId: String,
    val originId: String,
    val destinationId: String,
    var ttl: Int,
    val payloadType: String,
    val data: String,
    val timestamp: Long
) {
    val isBroadcast: Boolean
        get() = destinationId == "*"

    fun toJson(): String {
        val json = JSONObject()
        json.put("packetId", packetId)
        json.put("originId", originId)
        json.put("destinationId", destinationId)
        json.put("ttl", ttl)
        json.put("payloadType", payloadType)
        json.put("data", data)
        json.put("timestamp", timestamp)
        return json.toString()
    }

    companion object {
        fun fromJson(jsonString: String): MeshPacket? {
            return try {
                val json = JSONObject(jsonString)
                MeshPacket(
                    packetId = json.getString("packetId"),
                    originId = json.getString("originId"),
                    destinationId = json.getString("destinationId"),
                    ttl = json.optInt("ttl", 8),
                    payloadType = json.getString("payloadType"),
                    data = json.optString("data", ""),
                    timestamp = json.getLong("timestamp")
                )
            } catch (e: Exception) {
                null
            }
        }
    }
}
```

---

## 4. RelayController.kt

**Path:** `android/app/src/main/kotlin/com/liita/liita/RelayController.kt`

```kotlin
package com.liita.liita

import android.util.Log
import kotlinx.coroutines.*
import kotlin.random.Random

class RelayController(
    private val localDeviceId: String,
    private val deduplicationCache: DeduplicationCache,
    private val scope: CoroutineScope,
    private val onRelayAction: (MeshPacket) -> Unit
) {
    fun processForRelay(packet: MeshPacket) {
        // Drop if originating from local device
        if (packet.originId == localDeviceId) return

        // Drop if TTL <= 1
        if (packet.ttl <= 1) {
            Log.d("LiitaBLE", "[LiitaBLE] packet dropped (ttl <= 1): ${packet.packetId}")
            return
        }

        val degree = deduplicationCache.getDegree(packet.packetId)
        if (degree > 1) {
            Log.d("LiitaBLE", "[LiitaBLE] packet dropped (dedup already seen): ${packet.packetId}")
            return
        }

        // Decrement TTL
        val relayedPacket = packet.copy(ttl = packet.ttl - 1)

        // Jitter Delay: Random between 20 and 150 ms
        val jitterMs = Random.nextLong(20, 151)
        
        scope.launch {
            delay(jitterMs)
            val currentDegree = deduplicationCache.getDegree(packet.packetId)
            if (currentDegree <= 2) {
                Log.d("LiitaBLE", "[LiitaBLE] packet relayed: ${relayedPacket.packetId} ttl=${relayedPacket.ttl}")
                onRelayAction(relayedPacket)
            } else {
                Log.d("LiitaBLE", "[LiitaBLE] packet dropped (dedup during jitter window): ${packet.packetId}")
            }
        }
    }
}
```

---

## 5. DeduplicationCache.kt

**Path:** `android/app/src/main/kotlin/com/liita/liita/DeduplicationCache.kt`

```kotlin
package com.liita.liita

import android.util.Log

class DeduplicationCache(
    private val maxEntries: Int = 1000,
    private val maxAgeMillis: Long = 10 * 60 * 1000L // 10 minutes
) {
    private data class CacheEntry(
        var degree: Int,
        val timestamp: Long
    )

    private val map = LinkedHashMap<String, CacheEntry>(maxEntries, 0.75f, true)

    @Synchronized
    fun recordAndGetDegree(packetId: String): Int {
        pruneOldEntries()
        
        val entry = map[packetId]
        if (entry != null) {
            entry.degree++
            return entry.degree
        }

        // New entry
        if (map.size >= maxEntries) {
            // LinkedHashMap iterator gives oldest access first
            val eldestKey = map.keys.iterator().next()
            map.remove(eldestKey)
        }
        
        map[packetId] = CacheEntry(1, System.currentTimeMillis())
        return 1
    }

    @Synchronized
    fun getDegree(packetId: String): Int {
        pruneOldEntries()
        return map[packetId]?.degree ?: 0
    }

    private fun pruneOldEntries() {
        val now = System.currentTimeMillis()
        val iterator = map.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            if (now - entry.value.timestamp > maxAgeMillis) {
                iterator.remove()
            }
        }
    }

    @Synchronized
    fun clear() {
        map.clear()
    }
}
```

---

## 6. BlePeerRegistry.kt

**Path:** `android/app/src/main/kotlin/com/liita/liita/BlePeerRegistry.kt`

```kotlin
package com.liita.liita

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import java.util.concurrent.ConcurrentHashMap

/**
 * Tracks connected GATT clients for relaying packets.
 */
class BlePeerRegistry {
    // Map of MAC address to BluetoothGatt
    private val connectedGatts = ConcurrentHashMap<String, BluetoothGatt>()
    
    // Track discovered peers (Profile JSON) for the EventChannel
    private val discoveredPeers = ConcurrentHashMap<String, String>()

    fun addConnection(gatt: BluetoothGatt) {
        connectedGatts[gatt.device.address] = gatt
    }

    fun removeConnection(address: String) {
        connectedGatts.remove(address)
    }

    fun getAllConnections(): List<BluetoothGatt> {
        return connectedGatts.values.toList()
    }
    
    fun updatePeerProfile(deviceId: String, profileJson: String): Boolean {
        val existing = discoveredPeers[deviceId]
        if (existing != profileJson) {
            discoveredPeers[deviceId] = profileJson
            return true
        }
        return false
    }

    fun clear() {
        for (gatt in connectedGatts.values) {
            try {
                gatt.disconnect()
                gatt.close()
            } catch (e: Exception) {}
        }
        connectedGatts.clear()
        discoveredPeers.clear()
    }
}
```

---

## 7. Utils.kt

**Path:** `android/app/src/main/kotlin/com/liita/liita/Utils.kt`

```kotlin
package com.liita.liita

import android.util.Base64
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream

object Utils {
    fun compressAndEncode(jsonStr: String): String {
        val bos = ByteArrayOutputStream()
        GZIPOutputStream(bos).use { it.write(jsonStr.toByteArray()) }
        return Base64.encodeToString(bos.toByteArray(), Base64.NO_WRAP)
    }

    fun decodeAndDecompress(base64Str: String): String? {
        return try {
            val bytes = Base64.decode(base64Str, Base64.NO_WRAP)
            val bis = ByteArrayInputStream(bytes)
            GZIPInputStream(bis).bufferedReader().use { it.readText() }
        } catch (e: Exception) {
            null
        }
    }
}
```

---

## 8. mesh_service.dart

**Path:** `lib/core/services/mesh_service.dart`

```dart
import 'package:liita/core/models/mesh_packet.dart';
import 'package:liita/core/models/user_profile.dart';

/// Abstract interface for the Liita BLE mesh networking layer.
///
/// The active implementation is [FlutterMeshService], which bridges to the
/// native Android BLE stack via platform channels (MethodChannel + EventChannel).
abstract class MeshService {
  /// Starts the mesh network, advertising [localProfile] to nearby peers
  /// and beginning the discovery process.
  Future<void> startMesh(UserProfile localProfile);

  /// Stops the mesh network, tearing down all connections and timers.
  Future<void> stopMesh();

  /// Stream of peer profiles discovered on the mesh.
  ///
  /// Emits a [UserProfile] each time a new peer is found. Consumers should
  /// maintain their own set if deduplication is needed.
  Stream<UserProfile> get discoveredPeers;

  /// Stream of incoming packets (waves, messages, broadcasts) from peers.
  Stream<MeshPacket> get incomingPackets;

  /// Sends a [packet] over the mesh to the designated receiver.
  Future<void> sendPacket(MeshPacket packet);

  /// Whether the mesh is currently running.
  bool get isRunning;

  /// Stream that emits the current number of active (discovered) peers
  /// whenever the count changes.
  Stream<int> get activePeerCount;

  // ---------------------------------------------------------------------------
  // Duty-cycle control
  // ---------------------------------------------------------------------------

  /// Switch to foreground duty cycle: scan for 5 s, pause for 10 s, repeat.
  ///
  /// Call this when the app returns to the foreground from background.
  Future<void> setForegroundMode();

  /// Switch to background duty cycle: scan for 3 s, pause for 20 s, repeat.
  ///
  /// Call this when the app moves to [AppLifecycleState.paused] or
  /// [AppLifecycleState.hidden].
  Future<void> setBackgroundMode();

  /// Override to continuous scanning — no duty-cycling pauses.
  ///
  /// Call this when a chat conversation is actively open so messages
  /// are received in real time.
  Future<void> setContinuousMode();
}
```

---

## 9. mesh_service_flutter.dart

**Path:** `lib/core/services/mesh_service_flutter.dart`

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:liita/core/models/mesh_packet.dart';
import 'package:liita/core/models/user_profile.dart';
import 'package:liita/core/services/mesh_service.dart';

/// Real [MeshService] implementation that bridges to native BLE mesh code
/// via Flutter platform channels.
///
/// Uses a [MethodChannel] for request/response calls (start, stop, send) and
/// two [EventChannel]s for continuous streams (peer discovery, incoming
/// packets). The native side is expected to handle the actual BLE advertising,
/// scanning, GATT server/client, and mesh routing.
class FlutterMeshService implements MeshService {
  FlutterMeshService();

  // ---------------------------------------------------------------------------
  // Platform channels
  // ---------------------------------------------------------------------------

  static const _methodChannel = MethodChannel('com.liita.app/mesh');
  static const _peersEventChannel = EventChannel('com.liita.app/peers');
  static const _packetsEventChannel = EventChannel('com.liita.app/packets');

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  bool _isRunning = false;

  final _discoveredDeviceIds = <String>{};

  final _peerCountController = StreamController<int>.broadcast();

  StreamSubscription<UserProfile>? _peerCountSubscription;

  // Lazily initialised broadcast streams from event channels.
  Stream<UserProfile>? _peersStream;
  Stream<MeshPacket>? _packetsStream;

  // ---------------------------------------------------------------------------
  // MeshService interface
  // ---------------------------------------------------------------------------

  @override
  bool get isRunning => _isRunning;

  @override
  Stream<UserProfile> get discoveredPeers {
    _peersStream ??= _peersEventChannel
        .receiveBroadcastStream()
        .map<UserProfile>((dynamic event) {
      final json = _decodeEvent(event);
      return UserProfile.fromJson(json);
    }).asBroadcastStream();
    return _peersStream!;
  }

  @override
  Stream<MeshPacket> get incomingPackets {
    _packetsStream ??= _packetsEventChannel
        .receiveBroadcastStream()
        .map<MeshPacket>((dynamic event) {
      final json = _decodeEvent(event);
      return MeshPacket.fromJson(json);
    }).asBroadcastStream();
    return _packetsStream!;
  }

  @override
  Stream<int> get activePeerCount => _peerCountController.stream;

  @override
  Future<void> startMesh(UserProfile localProfile) async {
    if (_isRunning) return;

    await _methodChannel.invokeMethod<void>(
      'startMesh',
      {'profileJson': jsonEncode(localProfile.toJson())},
    );

    _isRunning = true;
    _discoveredDeviceIds.clear();

    // Track unique device IDs and emit updated peer counts.
    _peerCountSubscription = discoveredPeers.listen((profile) {
      if (_discoveredDeviceIds.add(profile.deviceId)) {
        _peerCountController.add(_discoveredDeviceIds.length);
      }
    });
  }

  @override
  Future<void> stopMesh() async {
    if (!_isRunning) return;

    await _methodChannel.invokeMethod<void>('stopMesh');
    _isRunning = false;

    await _peerCountSubscription?.cancel();
    _peerCountSubscription = null;
    _discoveredDeviceIds.clear();
    _peerCountController.add(0);
  }

  @override
  Future<void> sendPacket(MeshPacket packet) async {
    if (!_isRunning) return;

    await _methodChannel.invokeMethod<void>(
      'sendPacket',
      {'packetJson': jsonEncode(packet.toJson())},
    );
  }

  @override
  Future<void> setForegroundMode() async {
    if (!_isRunning) return;
    await _methodChannel.invokeMethod<void>('setForegroundMode');
  }

  @override
  Future<void> setBackgroundMode() async {
    if (!_isRunning) return;
    await _methodChannel.invokeMethod<void>('setBackgroundMode');
  }

  @override
  Future<void> setContinuousMode() async {
    if (!_isRunning) return;
    await _methodChannel.invokeMethod<void>('setContinuousMode');
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Call when the service is permanently disposed.
  void dispose() {
    stopMesh();
    _peerCountController.close();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Decodes a platform channel event into a JSON map.
  ///
  /// The native side may send either a [Map] (automatically decoded by
  /// Flutter's standard method codec) or a JSON [String].
  static Map<String, dynamic> _decodeEvent(dynamic event) {
    if (event is Map) {
      return Map<String, dynamic>.from(event);
    }
    if (event is String) {
      return jsonDecode(event) as Map<String, dynamic>;
    }
    throw FormatException(
      'Unexpected event type from platform channel: ${event.runtimeType}',
    );
  }
}
```

---

## 10. mesh_packet.dart

**Path:** `lib/core/models/mesh_packet.dart`

```dart
/// Represents a packet in the Liita BLE mesh network.
///
/// Packets are the fundamental unit of communication — they carry waves,
/// messages, profile syncs, and more. Each packet has a TTL (starting at 8)
/// for relay control and a unique [packetId] for deduplication.
class MeshPacket {
  final String packetId;
  final String originId;
  final String destinationId;
  final int ttl;
  final PayloadType payloadType;
  final String data;
  final int timestamp;

  const MeshPacket({
    required this.packetId,
    required this.originId,
    required this.destinationId,
    this.ttl = 8,
    required this.payloadType,
    this.data = '',
    required this.timestamp,
  });

  /// Whether this is a broadcast packet (destination is '*').
  bool get isBroadcast => destinationId == '*';

  MeshPacket copyWith({
    String? packetId,
    String? originId,
    String? destinationId,
    int? ttl,
    PayloadType? payloadType,
    String? data,
    int? timestamp,
  }) {
    return MeshPacket(
      packetId: packetId ?? this.packetId,
      originId: originId ?? this.originId,
      destinationId: destinationId ?? this.destinationId,
      ttl: ttl ?? this.ttl,
      payloadType: payloadType ?? this.payloadType,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
    'packetId': packetId,
    'originId': originId,
    'destinationId': destinationId,
    'ttl': ttl,
    'payloadType': payloadType.code,
    'data': data,
    'timestamp': timestamp,
  };

  factory MeshPacket.fromJson(Map<String, dynamic> json) => MeshPacket(
    packetId: json['packetId'] as String,
    originId: json['originId'] as String,
    destinationId: json['destinationId'] as String,
    ttl: json['ttl'] as int? ?? 8,
    payloadType: PayloadType.fromCode(json['payloadType'] as String),
    data: json['data'] as String? ?? '',
    timestamp: json['timestamp'] as int,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeshPacket && packetId == other.packetId;

  @override
  int get hashCode => packetId.hashCode;

  @override
  String toString() =>
      'MeshPacket(${payloadType.code}: $originId→$destinationId, ttl=$ttl)';
}

/// Payload types for mesh packets — single-char codes for compact BLE transmission.
enum PayloadType {
  wave('w'),
  waveAccept('a'),
  text('t'),
  profileSync('p'),
  photoChunk('c'),
  broadcast('b'),
  ack('k'),
  game('g');

  final String code;
  const PayloadType(this.code);

  static PayloadType fromCode(String code) {
    return PayloadType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => throw ArgumentError('Unknown PayloadType code: $code'),
    );
  }
}
```

---

## 11. providers.dart

**Path:** `lib/core/providers/providers.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liita/core/models/user_profile.dart';
import 'package:liita/core/models/chat_message.dart';
import 'package:liita/core/models/broadcast_message.dart';
import 'package:liita/core/controllers/app_controller.dart';
import 'package:liita/core/services/database_service.dart';
import 'package:liita/core/services/mesh_service.dart';
import 'package:liita/core/services/mesh_service_flutter.dart';
import 'package:liita/core/services/crypto_service.dart';
import 'package:liita/core/services/notification_service.dart';
import 'package:liita/core/services/storage_service.dart';

// ---------------------------------------------------------------------------
// Core service singletons
// ---------------------------------------------------------------------------

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService();
});

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService.instance;
});

final meshServiceProvider = Provider<MeshService>((ref) {
  return FlutterMeshService();
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

final cryptoServiceProvider = Provider<CryptoService>((ref) {
  return CryptoServiceImpl();
});

final appControllerProvider = Provider<AppController>((ref) {
  return AppController(
    db: ref.watch(databaseServiceProvider),
    mesh: ref.watch(meshServiceProvider),
    crypto: ref.watch(cryptoServiceProvider),
    notifications: ref.watch(notificationServiceProvider),
  );
});

// ---------------------------------------------------------------------------
// Local profile state
// ---------------------------------------------------------------------------

final localProfileProvider = StateProvider<UserProfile?>((ref) => null);

final onboardingCompleteProvider = StateProvider<bool>((ref) => false);

// ---------------------------------------------------------------------------
// Peers (live from mesh)
// ---------------------------------------------------------------------------

final peersProvider = StreamProvider<List<UserProfile>>((ref) {
  final mesh = ref.watch(meshServiceProvider);
  final peers = <String, UserProfile>{};

  return mesh.discoveredPeers.map((newPeer) {
    peers[newPeer.deviceId] = newPeer;
    return peers.values.toList();
  });
});

final activePeerCountProvider = StreamProvider<int>((ref) {
  return ref.watch(meshServiceProvider).activePeerCount;
});

// ---------------------------------------------------------------------------
// Matches
// ---------------------------------------------------------------------------

final matchesProvider = FutureProvider<List<String>>((ref) async {
  final localProfile = ref.watch(localProfileProvider);
  if (localProfile == null) return [];
  final db = ref.watch(databaseServiceProvider);
  return db.getMatches(localProfile.deviceId);
});

final matchProfileProvider =
    FutureProvider.family<UserProfile?, String>((ref, deviceId) async {
  final db = ref.watch(databaseServiceProvider);
  return db.getProfile(deviceId);
});

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

final messagesProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, matchId) {
  final db = ref.watch(databaseServiceProvider);
  return db.watchMessages(matchId);
});

final unreadCountProvider =
    FutureProvider.family<int, String>((ref, matchId) async {
  final db = ref.watch(databaseServiceProvider);
  return db.getUnreadCount(matchId);
});

final totalUnreadProvider = FutureProvider<int>((ref) async {
  final localProfile = ref.watch(localProfileProvider);
  if (localProfile == null) return 0;
  final db = ref.watch(databaseServiceProvider);
  return db.getTotalUnreadCount(localProfile.deviceId);
});

// ---------------------------------------------------------------------------
// Broadcast (Lounge)
// ---------------------------------------------------------------------------

final broadcastsProvider = StreamProvider<List<BroadcastMessage>>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return db.watchBroadcasts();
});

// ---------------------------------------------------------------------------
// Wave tracking
// ---------------------------------------------------------------------------

/// Tracks deviceIds the local user has waved at (in-memory for UI state).
final wavedAtProvider = StateProvider<Set<String>>((ref) => {});

/// Tracks deviceIds that have waved at the local user.
final wavedByProvider = StateProvider<Set<String>>((ref) => {});

/// Tracks matched deviceIds (for celebration animation trigger).
final newMatchProvider = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// Navigation state
// ---------------------------------------------------------------------------

final selectedTabProvider = StateProvider<int>((ref) => 0);
```

---

## 12. radar_screen.dart

**Path:** `lib/features/radar/radar_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/models/mesh_packet.dart';
import 'package:liita/core/models/user_profile.dart';
import 'package:liita/core/providers/providers.dart';
import 'package:liita/core/widgets/avatar_widget.dart';
import 'package:uuid/uuid.dart';

final wavedPeersProvider = StateProvider<Set<String>>((ref) => {});

/// Passenger discovery — stacked card deck (Figma design).
class RadarScreen extends ConsumerStatefulWidget {
  const RadarScreen({super.key});

  @override
  ConsumerState<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends ConsumerState<RadarScreen> {
  int _frontIndex = 0;

  void _nextCard(int total) {
    if (total == 0) return;
    setState(() => _frontIndex = (_frontIndex + 1) % total);
  }

  @override
  Widget build(BuildContext context) {
    final peersAsync = ref.watch(peersProvider);
    final localProfile = ref.watch(localProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: peersAsync.when(
          data: (peers) => _buildContent(peers, localProfile),
          loading: () => _buildContent([], localProfile),
          error: (_, __) => _buildContent([], localProfile),
        ),
      ),
    );
  }

  Widget _buildContent(List<UserProfile> peers, UserProfile? localProfile) {
    return Column(
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text(
                'Radar',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                peers.isEmpty ? 'no one nearby' : '${peers.length} nearby',
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),

        // ── Card Stack ───────────────────────────────────────────────────────
        Expanded(
          child: peers.isEmpty
              ? const _EmptyState()
              : _CardStack(
                  peers: peers,
                  frontIndex: _frontIndex,
                  localProfile: localProfile,
                  onWave: (peer) => _sendWave(peer, localProfile),
                  onNext: () => _nextCard(peers.length),
                ),
        ),

        // ── Pagination dots ──────────────────────────────────────────────────
        if (peers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                peers.length.clamp(0, 6),
                (i) {
                  final isActive =
                      i == _frontIndex % peers.length.clamp(1, 6);
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isActive ? 16 : 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.textPrimary
                          : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                },
              ),
            ),
          ),

        // Space for floating tab bar
        const SizedBox(height: 84),
      ],
    );
  }

  Future<void> _sendWave(UserProfile peer, UserProfile? local) async {
    if (local == null) return;
    final mesh = ref.read(meshServiceProvider);
    final packet = MeshPacket(
      packetId: const Uuid().v4(),
      originId: local.deviceId,
      destinationId: peer.deviceId,
      ttl: 5,
      payloadType: PayloadType.wave,
      data: '${local.name}|${local.seatNumber}',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    await mesh.sendPacket(packet);
    ref.read(wavedPeersProvider.notifier).update((state) => {...state, peer.deviceId});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Wave sent to ${peer.name}'),
          backgroundColor: AppColors.surfaceLight,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        ),
      );
    }
  }
}

// ── Card Stack ───────────────────────────────────────────────────────────────

class _CardStack extends StatelessWidget {
  final List<UserProfile> peers;
  final int frontIndex;
  final UserProfile? localProfile;
  final void Function(UserProfile) onWave;
  final VoidCallback onNext;

  const _CardStack({
    required this.peers,
    required this.frontIndex,
    required this.localProfile,
    required this.onWave,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final count = peers.length.clamp(0, 4);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // Draw from back (highest stackPos) to front (stackPos == 0)
          for (int stackPos = count - 1; stackPos >= 0; stackPos--)
            _StackCard(
              peer: peers[(frontIndex + stackPos) % peers.length],
              isFront: stackPos == 0,
              scale: 1.0 - (stackPos * 0.04),
              translateY: stackPos * 28.0,
              opacity: 1.0 - (stackPos * 0.15),
              onWave: () => onWave(peers[frontIndex % peers.length]),
              onNext: onNext,
              stackDepth: stackPos,
            ),
        ],
      ),
    );
  }
}

class _StackCard extends StatelessWidget {
  final UserProfile peer;
  final bool isFront;
  final double scale;
  final double translateY;
  final double opacity;
  final VoidCallback onWave;
  final VoidCallback onNext;
  final int stackDepth;

  const _StackCard({
    required this.peer,
    required this.isFront,
    required this.scale,
    required this.translateY,
    required this.opacity,
    required this.onWave,
    required this.onNext,
    required this.stackDepth,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      transform: Matrix4.identity()
        ..translate(0.0, translateY)
        ..scale(scale),
      transformAlignment: Alignment.topCenter,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: double.infinity,
          height: 380,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.glassBorder, width: 1),
            boxShadow: isFront ? AppShadows.elevated : [],
          ),
          child: isFront
              ? _FrontCardContent(
                  peer: peer, onWave: onWave, onNext: onNext)
              : _BackCardContent(stackDepth: stackDepth),
        ),
      ),
    );
  }
}

class _FrontCardContent extends ConsumerWidget {
  final UserProfile peer;
  final VoidCallback onWave;
  final VoidCallback onNext;

  const _FrontCardContent({
    required this.peer,
    required this.onWave,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wavedPeers = ref.watch(wavedPeersProvider);
    final hasWaved = wavedPeers.contains(peer.deviceId);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Avatar + info ──
          Row(
            children: [
              AvatarWidget(profile: peer, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            peer.name,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text('·',
                              style: TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 13)),
                        ),
                        Text(
                          peer.seatNumber,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      peer.occupation,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Spacer(),

          // ── Icebreaker ──
          Text(
            '"${peer.icebreakerAnswer}"',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w300,
              height: 1.5,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),

          const Spacer(),

          // ── Buttons ──
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onNext,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: AppColors.glassBorder, width: 1),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: hasWaved ? null : onWave,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: hasWaved ? AppColors.surface : AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      hasWaved ? 'Wave Sent' : 'Wave',
                      style: TextStyle(
                        color: hasWaved ? AppColors.textTertiary : AppColors.textOnPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BackCardContent extends StatelessWidget {
  final int stackDepth;

  const _BackCardContent({required this.stackDepth});

  @override
  Widget build(BuildContext context) {
    if (stackDepth == 1) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Opacity(
          opacity: 0.4,
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 100,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 70,
                    height: 11,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.glassBorder, width: 1),
            ),
            child: const Icon(
              Icons.wifi_tethering_rounded,
              color: AppColors.textTertiary,
              size: 28,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Scanning for passengers',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Keep the app open while we search',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
```

---

## 13. main.dart

**Path:** `lib/main.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/services/database_service.dart';
import 'package:liita/core/services/crypto_service.dart';
import 'package:liita/core/services/storage_service.dart';
import 'package:liita/core/services/mesh_service_flutter.dart';
import 'package:liita/core/models/user_profile.dart';
import 'package:liita/core/providers/providers.dart';
import 'package:liita/router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize DatabaseService
  final db = DatabaseService();
  await db.initialize();

  // Initialize CryptoService
  final crypto = CryptoServiceImpl();
  await crypto.initialize();

  // Read onboarding state and stored profile from secure storage BEFORE runApp.
  // This guarantees the router gets the right initial location synchronously.
  final storage = StorageService.instance;
  final bool isOnboarded = await storage.isOnboardingComplete();
  final UserProfile? storedProfile = isOnboarded ? await storage.loadProfile() : null;

  // Initialize MeshService
  final mesh = FlutterMeshService();
  if (isOnboarded && storedProfile != null) {
    debugPrint('[main] Starting mesh for profile ${storedProfile.deviceId}');
    // Do not await, let it start in the background to avoid blocking UI frame
    mesh.startMesh(storedProfile);
  }

  debugPrint('[main] isOnboarded=$isOnboarded, profile=${storedProfile?.name}');

  runApp(
    ProviderScope(
      overrides: [
        databaseServiceProvider.overrideWithValue(db),
        cryptoServiceProvider.overrideWithValue(crypto),
        meshServiceProvider.overrideWithValue(mesh),
        // Seed the onboarding flag from storage
        onboardingCompleteProvider.overrideWith((ref) => isOnboarded && storedProfile != null),
        // Seed the local profile from storage (null if not onboarded)
        localProfileProvider.overrideWith((ref) => storedProfile),
      ],
      child: const LiitaApp(),
    ),
  );
}

class LiitaApp extends ConsumerWidget {
  const LiitaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Liita',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
```

---

## 14. AndroidManifest.xml

**Path:** `android/app/src/main/AndroidManifest.xml`

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <!-- BLE Permissions (Android 12+) -->
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    
    <!-- Legacy BLE Permissions (Android 11 and below) -->
    <uses-permission android:name="android.permission.BLUETOOTH" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
    
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />

    <!-- BLE hardware feature requirement -->
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />

    <application
        android:label="liita"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>

        <!-- BLE mesh foreground service -->
        <service android:name=".MeshForegroundService"
                 android:foregroundServiceType="connectedDevice"
                 android:exported="false" />

        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
```
