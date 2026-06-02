import Foundation

class DeduplicationCache {
    private var map: [String: Int] = [:]
    private var order: [String] = []
    private let maxEntries: Int
    private let queue = DispatchQueue(label: "com.liita.app.dedupCache")

    init(maxEntries: Int = 1000) {
        self.maxEntries = maxEntries
    }

    func recordAndGetDegree(packetId: String) -> Int {
        return queue.sync {
            let currentDegree = map[packetId] ?? 0
            let newDegree = currentDegree + 1
            
            if currentDegree == 0 {
                order.append(packetId)
                if order.count > maxEntries {
                    let eldest = order.removeFirst()
                    map.removeValue(forKey: eldest)
                }
            }
            map[packetId] = newDegree
            return newDegree
        }
    }

    func getDegree(packetId: String) -> Int {
        return queue.sync {
            return map[packetId] ?? 0
        }
    }

    func clear() {
        queue.async {
            self.map.removeAll()
            self.order.removeAll()
        }
    }
}
