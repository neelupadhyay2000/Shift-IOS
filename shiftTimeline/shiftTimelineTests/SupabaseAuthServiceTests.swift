import Foundation
import Models
import Services
@testable import shiftTimeline
import Supabase
import SwiftData
import Testing

// MARK: - Fake repo

/// In-process fake used only by tests. @MainActor + final gives implicit Sendable.
@MainActor
final class FakeProfileRepository: ProfileRepositing {
    private(set) var upsertedProfiles: [ProfileDTO] = []
    var shouldThrow = false

    func upsert(_ profile: ProfileDTO) async throws {
        if shouldThrow { throw URLError(.badServerResponse) }
        upsertedProfiles.append(profile)
    }
}

// MARK: - Initial state

@Suite("SupabaseAuthService — initial state")
@MainActor
struct SupabaseAuthServiceInitialStateTests {
    @Test("isAuthenticated is false before any sign-in")
    func isAuthenticatedFalse() {
        let svc = SupabaseAuthService()
        #expect(!svc.isAuthenticated)
    }

    @Test("session is nil before any sign-in")
    func sessionNil() {
        let svc = SupabaseAuthService()
        #expect(svc.session == nil)
    }

    @Test("currentUser is nil before any sign-in")
    func currentUserNil() {
        let svc = SupabaseAuthService()
        #expect(svc.currentUser == nil)
    }

    @Test("currentProfileID is nil before any sign-in")
    func currentProfileIDNil() {
        let svc = SupabaseAuthService()
        #expect(svc.currentProfileID == nil)
    }

    @Test("currentProfile is nil before any sign-in")
    func currentProfileNil() {
        let svc = SupabaseAuthService()
        #expect(svc.currentProfile == nil)
    }
}

// MARK: - Lifecycle

@Suite("SupabaseAuthService — lifecycle")
@MainActor
struct SupabaseAuthServiceLifecycleTests {
    @Test("stopListening before startListening does not crash")
    func stopBeforeStartIsIdempotent() {
        let svc = SupabaseAuthService()
        svc.stopListening() // must not crash
        #expect(svc.session == nil)
    }

    @Test("startListening twice does not create a second listener")
    func startListeningIsIdempotent() throws {
        let url = try #require(URL(string: "https://wrhrpyinkcopqsibmkrf.supabase.co"))
        let provider = SupabaseClientProvider(supabaseURL: url, supabaseKey: "test-anon-key")
        let repo = FakeProfileRepository()
        let svc = SupabaseAuthService()
        svc.startListening(client: provider.client, profileRepository: repo)
        svc.startListening(client: provider.client, profileRepository: repo)
        svc.stopListening()
        #expect(svc.session == nil)
    }

    @Test("dependency-injected init initialises without crash")
    func injectedInitDoesNotCrash() throws {
        let url = try #require(URL(string: "https://wrhrpyinkcopqsibmkrf.supabase.co"))
        let provider = SupabaseClientProvider(supabaseURL: url, supabaseKey: "test-anon-key")
        let repo = FakeProfileRepository()
        let svc = SupabaseAuthService(client: provider.client, profileRepository: repo)
        _ = svc
    }
}

// MARK: - upsertProfile

@Suite("SupabaseAuthService — upsertProfile")
@MainActor
struct SupabaseAuthServiceUpsertProfileTests {
    @Test("upsertProfile passes displayName to the repository")
    func upsertProfileForwardsDisplayName() async throws {
        let url = try #require(URL(string: "https://wrhrpyinkcopqsibmkrf.supabase.co"))
        let provider = SupabaseClientProvider(supabaseURL: url, supabaseKey: "test-anon-key")
        let repo = FakeProfileRepository()
        let svc = SupabaseAuthService(client: provider.client, profileRepository: repo)

        let userID = UUID()
        let user = try makeUser(id: userID, phone: "+14155550101", email: nil)
        await svc.upsertProfile(from: user, displayName: "Ada Lovelace")

        let profile = try #require(repo.upsertedProfiles.first)
        #expect(profile.id == userID)
        #expect(profile.displayName == "Ada Lovelace")
        #expect(profile.phone == "+14155550101")
    }

    @Test("upsertProfile with nil displayName stores nil in the DTO")
    func upsertProfileNilDisplayName() async throws {
        let url = try #require(URL(string: "https://wrhrpyinkcopqsibmkrf.supabase.co"))
        let provider = SupabaseClientProvider(supabaseURL: url, supabaseKey: "test-anon-key")
        let repo = FakeProfileRepository()
        let svc = SupabaseAuthService(client: provider.client, profileRepository: repo)

        let user = try makeUser(id: UUID(), phone: nil, email: "ada@example.com")
        await svc.upsertProfile(from: user, displayName: nil)

        let profile = try #require(repo.upsertedProfiles.first)
        #expect(profile.displayName == nil)
        #expect(profile.email == "ada@example.com")
    }

    @Test("upsertProfile updates currentProfile on success")
    func upsertProfileUpdatesCurrent() async throws {
        let url = try #require(URL(string: "https://wrhrpyinkcopqsibmkrf.supabase.co"))
        let provider = SupabaseClientProvider(supabaseURL: url, supabaseKey: "test-anon-key")
        let repo = FakeProfileRepository()
        let svc = SupabaseAuthService(client: provider.client, profileRepository: repo)

        let user = try makeUser(id: UUID(), phone: "+1415", email: nil)
        await svc.upsertProfile(from: user, displayName: "Ada")

        #expect(svc.currentProfile != nil)
        #expect(svc.currentProfile?.displayName == "Ada")
    }

    @Test("upsertProfile is non-fatal when the repository throws")
    func upsertProfileIsNonFatal() async throws {
        let url = try #require(URL(string: "https://wrhrpyinkcopqsibmkrf.supabase.co"))
        let provider = SupabaseClientProvider(supabaseURL: url, supabaseKey: "test-anon-key")
        let repo = FakeProfileRepository()
        repo.shouldThrow = true
        let svc = SupabaseAuthService(client: provider.client, profileRepository: repo)

        let user = try makeUser(id: UUID(), phone: nil, email: "ada@example.com")
        // Must not propagate the error
        await svc.upsertProfile(from: user, displayName: nil)

        // currentProfile stays nil — upsert failed silently
        #expect(svc.currentProfile == nil)
    }

    @Test("upsertProfile is a no-op when no profileRepository is injected")
    func upsertProfileNoOpWithoutRepo() async throws {
        // Parameterless init — no repo injected, no startListening called
        let svc = SupabaseAuthService()
        let user = try makeUser(id: UUID(), phone: nil, email: nil)
        await svc.upsertProfile(from: user, displayName: nil) // must not crash
        #expect(svc.currentProfile == nil)
    }
}

// MARK: - signOut

@Suite("SupabaseAuthService — signOut")
@MainActor
struct SupabaseAuthServiceSignOutTests {
    @Test("signOut is a no-op when startListening was never called")
    func signOutWithNoClientIsNoOp() async throws {
        let svc = SupabaseAuthService()
        // guard let client else { return } path — must not crash
        try await svc.signOut()
    }
}

// MARK: - Sign-out cache clearing

@Suite("SupabaseAuthService — cache clearing")
@MainActor
struct SupabaseAuthServiceCacheClearingTests {
    @Test("clearSyncedCaches deletes all OutboxEntry rows")
    func clearSyncedCachesDeletesOutboxEntries() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        context.insert(OutboxEntry(tableName: "events", rowID: UUID(), operation: "insert"))
        context.insert(OutboxEntry(tableName: "blocks", rowID: UUID(), operation: "update"))
        try context.save()

        let url = try #require(URL(string: "https://wrhrpyinkcopqsibmkrf.supabase.co"))
        let provider = SupabaseClientProvider(supabaseURL: url, supabaseKey: "test-anon-key")
        let repo = FakeProfileRepository()
        let svc = SupabaseAuthService(client: provider.client, profileRepository: repo, modelContext: context)

        svc.clearSyncedCaches()

        let count = try context.fetchCount(FetchDescriptor<OutboxEntry>())
        #expect(count == 0)
    }

    @Test("clearSyncedCaches preserves EventModel rows (local-only data is never deleted)")
    func clearSyncedCachesPreservesEventModel() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        context.insert(EventModel(title: "Wedding", date: .now, latitude: 37.7, longitude: -122.4))
        context.insert(OutboxEntry(tableName: "events", rowID: UUID(), operation: "insert"))
        try context.save()

        let url = try #require(URL(string: "https://wrhrpyinkcopqsibmkrf.supabase.co"))
        let provider = SupabaseClientProvider(supabaseURL: url, supabaseKey: "test-anon-key")
        let repo = FakeProfileRepository()
        let svc = SupabaseAuthService(client: provider.client, profileRepository: repo, modelContext: context)

        svc.clearSyncedCaches()

        let outboxCount = try context.fetchCount(FetchDescriptor<OutboxEntry>())
        #expect(outboxCount == 0)

        let eventCount = try context.fetchCount(FetchDescriptor<EventModel>())
        #expect(eventCount == 1)
    }

    @Test("clearSyncedCaches is a no-op when no modelContext is injected")
    func clearSyncedCachesNoOpWithoutContext() {
        let svc = SupabaseAuthService()
        svc.clearSyncedCaches() // guard let context else { return } path — must not crash
    }
}

// MARK: - Test helper

/// Creates a `User` by decoding a minimal GoTrue-style JSON payload.
///
/// supabase-swift decodes `User` with `.convertFromSnakeCase`, so our
/// decoder must match. Dates use `ISO8601DateFormatter` with a `Z`-suffix
/// fallback so both fractional-seconds and plain formats are accepted.
private func makeUser(id: UUID = UUID(), phone: String?, email: String?) throws -> User {
    let emailJSON = email.map { "\"\($0)\"" } ?? "null"
    let phoneJSON = phone.map { "\"\($0)\"" } ?? "null"
    let json = """
    {
        "id": "\(id.uuidString)",
        "aud": "authenticated",
        "role": "authenticated",
        "email": \(emailJSON),
        "phone": \(phoneJSON),
        "app_metadata": {},
        "user_metadata": {},
        "created_at": "2024-01-01T00:00:00Z",
        "updated_at": "2024-01-01T00:00:00Z",
        "is_anonymous": false
    }
    """
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .custom { dec in
        let container = try dec.singleValueContainer()
        let str = try container.decode(String.self)
        if let date = withFraction.date(from: str) { return date }
        if let date = plain.date(from: str) { return date }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Cannot parse date: \(str)"
        )
    }
    return try decoder.decode(User.self, from: Data(json.utf8))
}
