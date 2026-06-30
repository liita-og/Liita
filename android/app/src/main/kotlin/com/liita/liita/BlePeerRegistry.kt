package com.liita.liita

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap

/**
 * Tracks connected GATT clients for relaying packets.
 */
class BlePeerRegistry {
    // Map of MAC address to BluetoothGatt
    private val connectedGatts = ConcurrentHashMap<String, BluetoothGatt>()

    // Track discovered peers (Profile JSON) for the EventChannel
    private val discoveredPeers = ConcurrentHashMap<String, String>()

    // Track all known BluetoothDevice objects for ephemeral connections (keyed by MAC)
    private val knownDevices = ConcurrentHashMap<String, BluetoothDevice>()

    // FIX 2D: Map logical deviceId → BluetoothDevice for unicast routing
    private val deviceIdToDevice = ConcurrentHashMap<String, BluetoothDevice>()

    // Reverse of deviceIdToDevice — MAC → logical deviceId. Lets a raw scan hit
    // (which only has a MAC) be attributed to a deviceId for presence pings,
    // without doing a GATT connect/read.
    private val addressToDeviceId = ConcurrentHashMap<String, String>()

    fun addConnection(gatt: BluetoothGatt) {
        connectedGatts[gatt.device.address] = gatt
    }

    fun removeConnection(address: String) {
        connectedGatts.remove(address)
    }

    fun getAllConnections(): List<BluetoothGatt> {
        return connectedGatts.values.toList()
    }

    fun addKnownDevice(device: BluetoothDevice) {
        knownDevices[device.address] = device
    }

    fun getAllKnownDevices(): List<BluetoothDevice> {
        return knownDevices.values.toList()
    }
    
    fun updatePeerProfile(macAddress: String, profileJson: String): Boolean {
        val existing = discoveredPeers[macAddress]
        if (existing != profileJson) {
            discoveredPeers[macAddress] = profileJson
            // FIX 2D: Record the deviceId → BluetoothDevice mapping when we learn the profile
            knownDevices[macAddress]?.let { device ->
                try {
                    val deviceId = JSONObject(profileJson).getString("deviceId")
                    deviceIdToDevice[deviceId] = device
                    addressToDeviceId[macAddress] = deviceId
                } catch (_: Exception) {}
            }
            return true
        }
        return false
    }

    /** FIX 2D: Look up a device by its logical deviceId (from profile JSON). */
    fun getDeviceById(deviceId: String): BluetoothDevice? = deviceIdToDevice[deviceId]

    /** Look up the logical deviceId already profiled for a MAC, if any. */
    fun getDeviceIdForAddress(address: String): String? = addressToDeviceId[address]

    fun clear() {
        for (gatt in connectedGatts.values) {
            try {
                gatt.disconnect()
                gatt.close()
            } catch (e: Exception) {}
        }
        connectedGatts.clear()
        discoveredPeers.clear()
        knownDevices.clear()
        deviceIdToDevice.clear()
        addressToDeviceId.clear()
    }
}
