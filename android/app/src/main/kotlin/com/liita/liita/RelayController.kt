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

        // RC-15: recordAndGetDegree is the canonical atomic check-and-increment.
        // getDegree alone is non-atomic when called separately from handleIncomingGattWrite
        // which already called recordAndGetDegree. We trust the degree already recorded
        // upstream — just relay if degree == 1 (seen exactly once, never relayed).
        val degree = deduplicationCache.getDegree(packet.packetId)
        if (degree != 1) {
            Log.d("LiitaBLE", "[LiitaBLE] relay dropped (degree=$degree): ${packet.packetId}")
            return
        }

        // Decrement TTL
        val relayedPacket = packet.copy(ttl = packet.ttl - 1)

        // Jitter Delay: Random between 20 and 150 ms
        val jitterMs = Random.nextLong(20, 151)
        
        scope.launch {
            delay(jitterMs)
            // RC-15: After jitter, only relay if degree is STILL exactly 1.
            // If degree climbed to 2+ during the jitter window, another node
            // already relayed this packet and we should suppress.
            val currentDegree = deduplicationCache.getDegree(packet.packetId)
            if (currentDegree == 1) {
                Log.d("LiitaBLE", "[LiitaBLE] packet relayed: ${relayedPacket.packetId} ttl=${relayedPacket.ttl}")
                onRelayAction(relayedPacket)
            } else {
                Log.d("LiitaBLE", "[LiitaBLE] packet dropped (dedup during jitter window): ${packet.packetId}")
            }
        }
    }
}
