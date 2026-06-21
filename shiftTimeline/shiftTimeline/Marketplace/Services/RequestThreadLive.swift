import Foundation
import Supabase
import SwiftUI

/// Per-thread realtime presence for a service request's chat. Opens a Supabase
/// realtime channel filtered to `request_id = <id>` while the thread view is on
/// screen, decodes incoming INSERTs into ``RequestMessageDTO``, and merges them
/// into `messages` (deduped against optimistic sends by id).
///
/// Intentionally SEPARATE from ``RealtimeSyncService`` — this never touches
/// SwiftData; chat lives only in this in-memory buffer for the open thread.
@MainActor
@Observable
final class RequestThreadLive {

    /// Oldest → newest, deduped by id.
    private(set) var messages: [RequestMessageDTO] = []

    private let client: SupabaseClient
    private let requestID: UUID
    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?

    init(client: SupabaseClient, requestID: UUID) {
        self.client = client
        self.requestID = requestID
    }

    // MARK: Buffer mutation

    /// Seeds (or extends) the buffer with a fetched page.
    func seed(_ page: [RequestMessageDTO]) {
        messages = Self.merged(messages, withPage: page)
    }

    /// Applies one message (realtime insert or optimistic send), deduped by id.
    func apply(_ message: RequestMessageDTO) {
        messages = Self.merged(messages, with: message)
    }

    // MARK: Lifecycle (subscribe onAppear / tear down onDisappear)

    func start() {
        guard listenTask == nil else { return }
        let channel = client.channel("request:\(requestID.uuidString)")
        self.channel = channel
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "request_messages",
            filter: .eq("request_id", value: requestID.uuidString)
        )
        listenTask = Task { [weak self] in
            let decoder = JSONDecoder()
            do {
                try await channel.subscribeWithError()
            } catch {
                return
            }
            for await insert in inserts {
                guard self != nil else { break }
                if let dto = try? insert.decodeRecord(as: RequestMessageDTO.self, decoder: decoder) {
                    self?.apply(dto)
                }
            }
        }
    }

    func stop() {
        listenTask?.cancel()
        listenTask = nil
        if let channel {
            Task { await channel.unsubscribe() }
        }
        channel = nil
    }

    // MARK: - Pure merge/dedupe (unit-tested)

    /// Merges one incoming message: replaces an existing entry with the same id
    /// (so a realtime echo supersedes the optimistic copy), else inserts in
    /// `created_at` order. `nonisolated` so it's synchronously testable.
    nonisolated static func merged(
        _ existing: [RequestMessageDTO],
        with incoming: RequestMessageDTO
    ) -> [RequestMessageDTO] {
        var result = existing
        if let index = result.firstIndex(where: { $0.id == incoming.id }) {
            result[index] = incoming
            return result
        }
        result.append(incoming)
        result.sort { ($0.createdAt.value, $0.id.uuidString) < ($1.createdAt.value, $1.id.uuidString) }
        return result
    }

    /// Merges a fetched page into the buffer: union by id (existing wins so an
    /// optimistic/echoed row isn't clobbered by an older fetch), sorted.
    nonisolated static func merged(
        _ existing: [RequestMessageDTO],
        withPage page: [RequestMessageDTO]
    ) -> [RequestMessageDTO] {
        var byID: [UUID: RequestMessageDTO] = [:]
        for message in existing { byID[message.id] = message }
        for message in page where byID[message.id] == nil { byID[message.id] = message }
        return byID.values.sorted { ($0.createdAt.value, $0.id.uuidString) < ($1.createdAt.value, $1.id.uuidString) }
    }
}
