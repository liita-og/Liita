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
