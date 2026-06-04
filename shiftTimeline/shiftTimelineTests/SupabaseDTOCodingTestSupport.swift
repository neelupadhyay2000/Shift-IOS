import Foundation
@testable import shiftTimeline
import Testing

// MARK: - Shared helpers for Supabase DTO coding tests

/// Encodes an `Encodable` with a plain `JSONEncoder` and returns the top-level
/// JSON object — used to assert wire-format keys (snake_case) and values.
func jsonObject(from value: some Encodable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}

/// Decodes a DTO from a raw JSON string with a plain `JSONDecoder`, mimicking
/// the snake_case payload PostgREST returns.
func decodeDTO<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
    let data = try #require(json.data(using: .utf8))
    return try JSONDecoder().decode(type, from: data)
}

/// Round-trips a value through encode → decode with plain coders.
func roundTrip<T: Codable>(_ value: T) throws -> T {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(T.self, from: data)
}

/// A whole-second timestamp, so the millisecond-precision `timestamptz`
/// encoding round-trips byte-for-byte. (2026-05-28T20:26:40Z.)
let fixedTimestamp = Date(timeIntervalSince1970: 1_780_000_000)

/// `fixedTimestamp` wrapped for DTO timestamp fields.
let fixedPGTimestamp = PostgresTimestamp(fixedTimestamp)
