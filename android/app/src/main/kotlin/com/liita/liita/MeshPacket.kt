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
        json.put("p", packetId)
        json.put("o", originId)
        json.put("d", destinationId)
        json.put("l", ttl)
        json.put("y", payloadType)
        json.put("a", data)
        json.put("t", timestamp)
        return json.toString()
    }

    companion object {
        fun fromJson(jsonString: String): MeshPacket? {
            return try {
                val json = JSONObject(jsonString)
                MeshPacket(
                    packetId = json.getString("p"),
                    originId = json.getString("o"),
                    destinationId = json.getString("d"),
                    ttl = json.optInt("l", 8),
                    payloadType = json.getString("y"),
                    data = json.optString("a", ""),
                    timestamp = json.getLong("t")
                )
            } catch (e: Exception) {
                null
            }
        }
    }
}
