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
