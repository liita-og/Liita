import Foundation

struct Utils {
    static func compressAndEncode(_ jsonStr: String) -> String? {
        guard let data = jsonStr.data(using: .utf8) else { return nil }
        guard let compressed = try? (data as NSData).compressed(using: .zlib) as Data else { return nil }
        return compressed.base64EncodedString()
    }
    
    static func decodeAndDecompress(_ base64Str: String) -> String? {
        guard let data = Data(base64Encoded: base64Str) else { return nil }
        guard let decompressed = try? (data as NSData).decompressed(using: .zlib) as Data else { return nil }
        return String(data: decompressed, encoding: .utf8)
    }
}
