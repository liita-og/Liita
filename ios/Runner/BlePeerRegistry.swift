import Foundation
import CoreBluetooth

class BlePeerRegistry {
    private var connectedGatts: [String: CBPeripheral] = [:]
    private var discoveredPeers: [String: String] = [:]
    private let queue = DispatchQueue(label: "com.liita.app.peerRegistry")

    func addConnection(_ peripheral: CBPeripheral) {
        queue.async {
            self.connectedGatts[peripheral.identifier.uuidString] = peripheral
        }
    }

    func removeConnection(_ uuidString: String) {
        queue.async {
            self.connectedGatts.removeValue(forKey: uuidString)
        }
    }

    func getAllConnections() -> [CBPeripheral] {
        return queue.sync {
            return Array(connectedGatts.values)
        }
    }
    
    func updatePeerProfile(deviceId: String, profileJson: String) -> Bool {
        return queue.sync {
            let existing = discoveredPeers[deviceId]
            if existing != profileJson {
                discoveredPeers[deviceId] = profileJson
                return true
            }
            return false
        }
    }

    func clear() {
        queue.async {
            self.connectedGatts.removeAll()
            self.discoveredPeers.removeAll()
        }
    }
}
