import CloudKit
import Foundation
import SwiftData
import Models
import os

/// A Sendable wrapper for a CloudKit record deletion, safe to pass across actor boundaries.
public struct SharedDeletedRecord: Sendable {
    public let recordID: CKRecord.ID
    public let recordType: String

    public init(recordID: CKRecord.ID, recordType: String) {
        self.recordID = recordID
        self.recordType = recordType
    }
}

/// Maps CKRecords from the shared CloudKit database into the local SwiftData store.
///
/// `NSPersistentCloudKitContainer` (SwiftData's backing store) only mirrors the
/// **private** CloudKit database. Accepted CKShare records live in the shared database
/// and are never mirrored automatically. This syncer bridges that gap:
///
/// 1. Called by `SharedZoneSubscriptionManager` after each zone-change fetch.
/// 2. Parses `CD_`-prefixed fields (NSPersistentCloudKitContainer's naming convention).
/// 3. Upserts SwiftData objects by their stable `id` UUID — idempotent and safe
///    to call repeatedly without creating duplicates.
/// 4. Maintains a UserDefaults cache of `recordName → UUID` so relationship
///    references can be resolved across fetch batches and deletions can be matched.
@MainActor
public final class SharedRecordSyncer {

    private static let logger = Logger(subsystem: "com.shift.cloudkit", category: "SharedRecordSyncer")

    private static let uuidCacheKey = "com.shift.sharedRecordNameToUUID"
    private static let typeCacheKey = "com.shift.sharedRecordNameToType"

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Public

    public func merge(modified: [CKRecord], deleted: [SharedDeletedRecord]) throws {
        // Build / extend the persistent record-name → UUID and record-name → type caches.
        var uuidCache = Self.loadCache(key: Self.uuidCacheKey)
        var typeCache = Self.loadCache(key: Self.typeCacheKey)
        for record in modified {
            if let uuidString = Self.uuidString(from: record) {
                uuidCache[record.recordID.recordName] = uuidString
                typeCache[record.recordID.recordName] = record.recordType
            }
        }
        Self.saveCache(uuidCache, key: Self.uuidCacheKey)
        Self.saveCache(typeCache, key: Self.typeCacheKey)

        // Process in dependency order so relationships can be wired in one pass.
        for record in modified where record.recordType == "CD_EventModel"     { try upsertEvent(from: record) }
        for record in modified where record.recordType == "CD_TimelineTrack"  { try upsertTrack(from: record, uuidCache: uuidCache) }
        for record in modified where record.recordType == "CD_TimeBlockModel" { try upsertBlock(from: record, uuidCache: uuidCache) }
        for record in modified where record.recordType == "CD_VendorModel"    { try upsertVendor(from: record, uuidCache: uuidCache) }
        for deletion in deleted                                               { try handleDeletion(deletion, uuidCache: uuidCache, typeCache: typeCache) }

        try context.save()
        Self.logger.info("SharedRecordSyncer merged \(modified.count) records, \(deleted.count) deletions")
    }

    // MARK: - EventModel

    private func upsertEvent(from record: CKRecord) throws {
        guard let uuid = Self.uuid(from: record) else {
            Self.logger.warning("CD_EventModel: missing CD_id, skipping \(record.recordID.recordName)")
            return
        }

        let event: EventModel
        if let existing = try fetchEvent(id: uuid) {
            event = existing
        } else {
            event = EventModel(title: "", date: .now, latitude: 0, longitude: 0)
            event.id = uuid
            context.insert(event)
        }

        if let v = record["CD_title"] as? String           { event.title = v }
        if let v = record["CD_date"] as? Date              { event.date = v }
        if let v = record["CD_latitude"] as? Double        { event.latitude = v }
        if let v = record["CD_longitude"] as? Double       { event.longitude = v }
        if let v = record["CD_ownerRecordName"] as? String { event.ownerRecordName = v }
        if let v = record["CD_shareURL"] as? String        { event.shareURL = v }
        if let v = record["CD_sunsetTime"] as? Date        { event.sunsetTime = v }
        if let v = record["CD_goldenHourStart"] as? Date   { event.goldenHourStart = v }
        if let raw = record["CD_status"] as? String,
           let v = EventStatus(rawValue: raw)              { event.status = v }
    }

    // MARK: - TimelineTrack

    private func upsertTrack(from record: CKRecord, uuidCache: [String: String]) throws {
        guard let uuid = Self.uuid(from: record) else { return }

        let track: TimelineTrack
        if let existing = try fetchTrack(id: uuid) {
            track = existing
        } else {
            track = TimelineTrack(name: "", sortOrder: 0)
            track.id = uuid
            context.insert(track)
        }

        if let v = record["CD_name"] as? String        { track.name = v }
        if let v = record["CD_sortOrder"] as? NSNumber { track.sortOrder = v.intValue }
        if let v = record["CD_isDefault"] as? NSNumber { track.isDefault = v.boolValue }

        if let ref = record["CD_event"] as? CKRecord.Reference,
           let eventUUID = resolve(ref, cache: uuidCache) {
            track.event = try fetchEvent(id: eventUUID)
        }
    }

    // MARK: - TimeBlockModel

    private func upsertBlock(from record: CKRecord, uuidCache: [String: String]) throws {
        guard let uuid = Self.uuid(from: record) else { return }

        let block: TimeBlockModel
        if let existing = try fetchBlock(id: uuid) {
            block = existing
        } else {
            block = TimeBlockModel(title: "", scheduledStart: .now, duration: 0)
            block.id = uuid
            context.insert(block)
        }

        if let v = record["CD_title"] as? String            { block.title = v }
        if let v = record["CD_scheduledStart"] as? Date     { block.scheduledStart = v }
        if let v = record["CD_originalStart"] as? Date      { block.originalStart = v }
        if let v = record["CD_duration"] as? Double         { block.duration = v }
        if let v = record["CD_minimumDuration"] as? Double  { block.minimumDuration = v }
        if let v = record["CD_isPinned"] as? NSNumber       { block.isPinned = v.boolValue }
        if let v = record["CD_notes"] as? String            { block.notes = v }
        if let v = record["CD_colorTag"] as? String         { block.colorTag = v }
        if let v = record["CD_icon"] as? String             { block.icon = v }
        if let v = record["CD_isOutdoor"] as? NSNumber      { block.isOutdoor = v.boolValue }
        if let v = record["CD_venueAddress"] as? String     { block.venueAddress = v }
        if let v = record["CD_venueName"] as? String        { block.venueName = v }
        if let v = record["CD_blockLatitude"] as? Double    { block.blockLatitude = v }
        if let v = record["CD_blockLongitude"] as? Double   { block.blockLongitude = v }
        if let v = record["CD_isTransitBlock"] as? NSNumber { block.isTransitBlock = v.boolValue }
        if let raw = record["CD_status"] as? String,
           let v = BlockStatus(rawValue: raw)               { block.status = v }

        if let ref = record["CD_track"] as? CKRecord.Reference,
           let trackUUID = resolve(ref, cache: uuidCache) {
            block.track = try fetchTrack(id: trackUUID)
        }
    }

    // MARK: - VendorModel

    private func upsertVendor(from record: CKRecord, uuidCache: [String: String]) throws {
        guard let uuid = Self.uuid(from: record) else { return }

        let vendor: VendorModel
        if let existing = try fetchVendor(id: uuid) {
            vendor = existing
        } else {
            vendor = VendorModel(name: "", role: .custom)
            vendor.id = uuid
            context.insert(vendor)
        }

        if let v = record["CD_name"] as? String                         { vendor.name = v }
        if let v = record["CD_phone"] as? String                        { vendor.phone = v }
        if let v = record["CD_email"] as? String                        { vendor.email = v }
        if let v = record["CD_cloudKitRecordName"] as? String           { vendor.cloudKitRecordName = v }
        if let v = record["CD_notificationThreshold"] as? Double        { vendor.notificationThreshold = v }
        if let v = record["CD_hasAcknowledgedLatestShift"] as? NSNumber { vendor.hasAcknowledgedLatestShift = v.boolValue }
        // Always overwrite — nil means "no pending shift" which is also meaningful.
        vendor.pendingShiftDelta = record["CD_pendingShiftDelta"] as? Double
        if let raw = record["CD_role"] as? String,
           let v = VendorRole(rawValue: raw)                            { vendor.role = v }

        if let ref = record["CD_event"] as? CKRecord.Reference,
           let eventUUID = resolve(ref, cache: uuidCache) {
            vendor.event = try fetchEvent(id: eventUUID)
        }
    }

    // MARK: - Deletions

    private func handleDeletion(
        _ deletion: SharedDeletedRecord,
        uuidCache: [String: String],
        typeCache: [String: String]
    ) throws {
        let name = deletion.recordID.recordName
        guard let uuidString = uuidCache[name], let uuid = UUID(uuidString: uuidString) else {
            Self.logger.info("No cached UUID for deleted record \(name) — skipping")
            return
        }
        let type = deletion.recordType.isEmpty ? (typeCache[name] ?? "") : deletion.recordType
        switch type {
        case "CD_EventModel":
            if let obj = try fetchEvent(id: uuid)   { context.delete(obj) }
        case "CD_TimelineTrack":
            if let obj = try fetchTrack(id: uuid)   { context.delete(obj) }
        case "CD_TimeBlockModel":
            if let obj = try fetchBlock(id: uuid)   { context.delete(obj) }
        case "CD_VendorModel":
            if let obj = try fetchVendor(id: uuid)  { context.delete(obj) }
        default:
            Self.logger.info("Unhandled deletion type: \(type)")
        }
    }

    // MARK: - Typed fetch helpers

    private func fetchEvent(id: UUID) throws -> EventModel? {
        try context.fetch(FetchDescriptor<EventModel>(predicate: #Predicate { $0.id == id })).first
    }

    private func fetchTrack(id: UUID) throws -> TimelineTrack? {
        try context.fetch(FetchDescriptor<TimelineTrack>(predicate: #Predicate { $0.id == id })).first
    }

    private func fetchBlock(id: UUID) throws -> TimeBlockModel? {
        try context.fetch(FetchDescriptor<TimeBlockModel>(predicate: #Predicate { $0.id == id })).first
    }

    private func fetchVendor(id: UUID) throws -> VendorModel? {
        try context.fetch(FetchDescriptor<VendorModel>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: - Helpers

    /// Extracts the SwiftData UUID from `CD_id` (or `id` as fallback).
    /// NSPersistentCloudKitContainer stores UUIDs as Strings in CloudKit.
    private static func uuid(from record: CKRecord) -> UUID? {
        for key in ["CD_id", "id"] {
            if let str = record[key] as? String, let uuid = UUID(uuidString: str) { return uuid }
            if let uuid = record[key] as? UUID { return uuid }
        }
        return nil
    }

    private static func uuidString(from record: CKRecord) -> String? {
        uuid(from: record)?.uuidString
    }

    private func resolve(_ ref: CKRecord.Reference, cache: [String: String]) -> UUID? {
        guard let uuidString = cache[ref.recordID.recordName] else { return nil }
        return UUID(uuidString: uuidString)
    }

    // MARK: - Cache persistence

    private static func loadCache(key: String) -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    private static func saveCache(_ cache: [String: String], key: String) {
        UserDefaults.standard.set(cache, forKey: key)
    }
}
