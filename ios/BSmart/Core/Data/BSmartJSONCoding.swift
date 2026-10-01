import Foundation

enum BSmartJSONCoding {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let interval = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: interval)
            }

            let value = try container.decode(String.self)
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
                return date
            }
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported ISO-8601 date: \(value)"
            )
        }
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

// Large research snapshots must not decode or touch disk on the UI executor.
actor BSmartContentIO {
    static let shared = BSmartContentIO()

    func decode<Value: Decodable>(_ type: Value.Type, from data: Data,
                                  iso8601Dates: Bool = false) throws -> Value {
        try Task.checkCancellation()
        let decoder = iso8601Dates ? BSmartJSONCoding.makeDecoder() : JSONDecoder()
        return try decoder.decode(type, from: data)
    }

    func read<Value: Decodable>(_ type: Value.Type, from url: URL,
                                maximumBytes: Int = 16_777_216, iso8601Dates: Bool = false) -> Value? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maximumBytes, let data = try? Data(contentsOf: url),
              data.count <= maximumBytes else { return nil }
        return try? decode(type, from: data, iso8601Dates: iso8601Dates)
    }

    func persist<Value: Encodable>(_ value: Value, to url: URL?) throws -> (data: Data, savedToFile: Bool) {
        let data = try JSONEncoder().encode(value)
        guard let url else { return (data, false) }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return (data, true)
        } catch {
            return (data, false)
        }
    }
}
