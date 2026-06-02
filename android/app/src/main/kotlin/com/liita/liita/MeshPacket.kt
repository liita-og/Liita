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
