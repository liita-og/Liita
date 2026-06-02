import Foundation

class RelayController {
    private let localDeviceId: String
    private let deduplicationCache: DeduplicationCache
    private let onRelayAction: (MeshPacket) -> Void
    
    init(localDeviceId: String, deduplicationCache: DeduplicationCache, onRelayAction: @escaping (MeshPacket) -> Void) {
        self.localDeviceId = localDeviceId
        self.deduplicationCache = deduplicationCache
        self.onRelayAction = onRelayAction
    }
    
    func processForRelay(packet: MeshPacket) {
        // 1. Drop if originating from local device
        if packet.originId == localDeviceId { return }

        // 2. Drop if TTL <= 1
        if packet.ttl <= 1 { return }

        // 3. Decrement TTL
        var relayedPacket = packet
        relayedPacket.ttl -= 1

        // 4. Jitter Delay (10ms to 220ms) like Bitchat
        let jitterMs = Int.random(in: 10...220)
        
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(jitterMs)) { [weak self] in
            guard let self = self else { return }
            
            let degree = self.deduplicationCache.getDegree(packetId: packet.packetId)
            
            if degree <= 2 {
                self.onRelayAction(relayedPacket)
            }
        }
    }
}
