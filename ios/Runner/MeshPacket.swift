import Foundation

struct MeshPacket: Codable {
    let packetId: String
    let originId: String
    let destinationId: String
    var ttl: Int
    let payloadType: String
    let data: String
    let timestamp: Int64

    var isBroadcast: Bool {
        return destinationId == "*"
    }

    func toJsonString() -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func fromJson(_ jsonString: String) -> MeshPacket? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(MeshPacket.self, from: data)
    }
}
