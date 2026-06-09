# SHIFT — Architecture Design Document

> **Status:** Living document · **Last updated:** 2026-06-09
> **Scope:** The `Shift-IOS` repository — the SHIFT iOS/watchOS app and its Supabase backend.

SHIFT is an event-timeline planner. Planners build a multi-track, block-by-block
schedule for an event ("the timeline"), then run it live on the day-of, shifting
blocks in real time while collaborators ("vendors") stay in sync. The product
spans an iPhone app, a Home Screen widget, a Live Activity, a watchOS app +
complication, and a Supabase (Postgres + Realtime + Edge Functions + APNs)
backend.

This document describes the system's structure, the major subsystems, and the
key design decisions and invariants that hold them together.

---

## 1. System Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          Apple devices (per user)                         │
│                                                                            │
│   ┌─────────────┐   App Group    ┌──────────────┐   WatchConnectivity    │
│   │  iPhone app │◄──UserDefaults─►│ Home widget  │   (WCSession)          │
│   │  (SwiftUI)  │   + SwiftData   │ Live Activity│◄──────────┐            │
│   └──────┬──────┘   store         └──────────────┘           │            │
│          │                                          ┌────────▼─────────┐  │
│          │  SwiftData (local source of truth)       │   watchOS app    │  │
│          │  + offline Outbox queue                  │   + complication │  │
│          │                                          └──────────────────┘  │
└──────────┼─────────────────────────────────────────────────────────────────┘
           │
           │  HTTPS (PostgREST upsert/select) · WebSocket (Realtime) · APNs
           ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                              Supabase backend                              │
│                                                                            │
│   Postgres (RLS-enforced)        Realtime          Edge Function          │
│   profiles, events, tracks,  ──► publication  ──►  shift-notify (Deno)     │
│   blocks, event_vendors,         (per-event                │              │
│   block_vendors, block_deps,      channels)                ▼              │
│   shift_records, device_tokens                          APNs push          │
│   + RPCs: can_access_event,                                                │
│     claim_invite, normalize_phone                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Architectural style:** local-first, offline-capable client with an
eventually-consistent cloud sync layer.

- The **local SwiftData store is the source of truth** for the UI. Every write
  completes against SwiftData immediately; the UI never blocks on the network.
- The cloud (**Supabase**) is the **sync and sharing fabric**. Writes are queued
  locally and flushed asynchronously; reads converge via initial hydration,
  delta catch-up, and live Realtime.
- Convergence rules are **idempotent upserts**, **soft-delete tombstones**, and
  **last-write-wins** keyed on a server `updated_at`.

> **Historical note:** The app originally synced via CloudKit
> (`NSPersistentCloudKitContainer`). It migrated to a Supabase-backed model to
> enable cross-account sharing with non-iCloud collaborators. The fingerprints
> of that migration are visible in the schema history (§4.3) — schema versions
> V10→V11 drop CloudKit-only fields, and V11→V16 add the Supabase sync columns.

---

## 2. Repository Layout

```
Shift-IOS/
├── shiftTimeline/
│   ├── SHIFT/SHIFTKit/                  # Local Swift package — shared, testable core
│   │   ├── Package.swift                #   swift-tools 6.0, iOS 17+/watchOS 10+
│   │   └── Sources/
│   │       ├── Models/                  #   @Model domain types + 16 schema versions
│   │       ├── Engine/                  #   RippleEngine + collision/dependency logic
│   │       ├── Services/                #   Persistence, repositories, domain services
│   │       ├── ObjCException/           #   Obj-C try/catch shim for NSException
│   │       └── TestSupport/             #   Fakes, builders, fixtures
│   ├── shiftTimeline/                   # iPhone app target
│   │   ├── Timeline/ Execution/ Events/ Vendors/ Templates/ …  (feature modules)
│   │   ├── Sync/                        #   Supabase sync layer (Outbox, Realtime, DTOs…)
│   │   ├── Auth/ Navigation/ Notifications/ Paywall/ …
│   │   └── shiftTimelineApp.swift       #   @main entry point + AppDelegate
│   ├── shiftTimelineWidget/             # WidgetKit extension + Live Activity
│   ├── shiftTimelineWatch Watch App/    # watchOS app
│   ├── shiftTimelineWatchWidget/        # watchOS complication
│   ├── shiftTimelineTests/              # Unit tests (Swift Testing)
│   └── shiftTimelineUITests/            # UI tests (XCUITest, page objects)
├── supabase/
│   ├── migrations/                      # Append-only SQL schema + RLS + RPCs
│   ├── functions/shift-notify/          # Deno/TypeScript Edge Function (APNs push)
│   └── tests/                           # pgTAP-style SQL test suites
├── Config/                              # xcconfig (Debug/Release/Secrets template)
├── ci_scripts/                          # Xcode Cloud build phases
└── .xcode/workflows/                    # Xcode Cloud workflow definitions (canonical YAML)
```

### 2.1 The SHIFTKit package — why a local package?

The domain core lives in a local Swift package, **SHIFTKit**, with four products:

| Product       | Depends on                  | Responsibility                                            |
| ------------- | --------------------------- | --------------------------------------------------------- |
| `Models`      | —                           | `@Model` domain types, enums, schema versions, DTOs-shared|
| `Engine`      | `Models`                    | Pure timeline math (ripple, collisions, dependencies)     |
| `Services`    | `Models`, `Engine`, `ObjCException` | Persistence, repositories, weather/sunset/etc.    |
| `TestSupport` | `Models`, `Services`        | Fakes, fixture builders for unit + UI tests               |

Packaging the core this way enforces a **dependency direction** (UI → Services →
Engine → Models, never the reverse), makes the business logic **buildable and
testable without the app or a simulator UI**, and lets the **app, widget, and
watch targets all share one definition** of the model and persistence layer.

---

## 3. Layered Architecture

The system is layered top-to-bottom; each layer depends only on those below it.

```
   ┌─────────────────────────────────────────────────────────────┐
   │  Presentation   SwiftUI views · @Query · @State · @Observable │   app targets
   │                 widget · Live Activity · watch app            │
   ├─────────────────────────────────────────────────────────────┤
   │  Coordination   Repository protocols · Sync coordinators ·    │   app + SHIFTKit
   │                 Auth · DeepLink · Notification routing        │
   ├─────────────────────────────────────────────────────────────┤
   │  Domain logic   RippleEngine · transitions · report/weather   │   SHIFTKit/Engine
   │                 services (pure, deterministic)                │   + Services
   ├─────────────────────────────────────────────────────────────┤
   │  Persistence    SwiftData @Model · PersistenceController ·    │   SHIFTKit/Models
   │                 repositories · Outbox queue                   │   + Services
   ├─────────────────────────────────────────────────────────────┤
   │  Sync / Backend Supabase (Postgres + RLS + Realtime + Edge)   │   Sync/ + supabase/
   └─────────────────────────────────────────────────────────────┘
```

### 3.1 Presentation layer

SwiftUI-native, **view-centric** rather than classic MVVM. There are no
freestanding view-model objects for most screens. Instead:

- Views read persisted state directly with `@Query` and
  `@Environment(\.modelContext)`.
- Local UI state lives in `@State` on the view.
- Cross-cutting services are injected through the SwiftUI environment as
  `@Observable` objects (`SupabaseAuthService`, `WatchSessionManager`,
  `LiveActivityManager`, `DeepLinkRouter`) or as repository protocols.

This keeps screens close to the data and leans on SwiftData's change tracking to
re-render automatically when sync mutates the store. Complex screens
(`Timeline/TimelineBuilderView.swift`, `Execution/LiveDashboardView.swift`)
compose smaller subviews rather than extracting a view model.

### 3.2 Coordination layer

This layer bridges views to persistence and the network without leaking either
into the other:

- **Repository protocols** (`EventRepositing`, `TrackRepositing`,
  `BlockRepositing`, `VendorRepositing`, `ShiftRecordRepositing`) abstract all
  writes. Reads go through `@Query`.
- **Sync coordinators** (`WriteThroughCoordinator`, `OutboxCoordinator`,
  `OutboxFlusher`, Realtime services) mirror local writes to Supabase and merge
  remote changes back in.
- **Auth, deep linking, and notification routing** translate external events
  (sign-in, URLs, pushes) into navigation and data operations.

### 3.3 Domain logic layer

Pure, deterministic, I/O-free logic lives in `Engine` and `Services`:

- The **RippleEngine** and its collaborators (§5).
- **State transitions** modeled as pure functions on the model
  (`EventModel+GoLiveTransition`, `EventModel+LiveModeTransition`).
- **Domain services** that do touch I/O (weather, sunset, travel time, reports,
  subscriptions) but keep their network/disk edges injectable for testing.

Pure functions here are the heavily unit-tested heart of the app.

---

## 4. Data Model & Persistence

### 4.1 Domain entities

All persisted entities are SwiftData `@Model` classes in
`SHIFTKit/Sources/Models`. The aggregate root is `EventModel`.

```
EventModel ──┬── tracks:        [TimelineTrack]   (cascade)
             ├── vendors:       [VendorModel]     (cascade)
             └── shiftRecords:  [ShiftRecord]     (cascade, append-only audit)

TimelineTrack ──── blocks:      [TimeBlockModel]  (cascade)

TimeBlockModel ──┬─ assignedVendors: [VendorModel]   (many-to-many, nullify)
                 ├─ dependencies:    [TimeBlockModel] (self-ref, explicit ordering)
                 └─ dependents:      [TimeBlockModel] (self-ref, inverse)
```

| Entity           | Role                                                                                     |
| ---------------- | ---------------------------------------------------------------------------------------- |
| `EventModel`     | Root aggregate. Title, date, location, `status` (planning→live→completed), owner, weather/sunset cache, post-event report, sync `updatedAt`/`ownerId`. |
| `TimelineTrack`  | A named lane within an event (e.g. "Ceremony", "Reception"). Exactly one `isDefault` track per event. |
| `TimeBlockModel` | A scheduled activity. `scheduledStart`/`originalStart`/`duration`, `status`, `isPinned` (immovable), `isOutdoor`, `isTransitBlock`, voice-memo + location metadata. |
| `VendorModel`    | A collaborator on an event. Role, contact, notification threshold, invite/claim state (`invitedAt`/`profileId`/`acceptedAt`), `pendingShiftDelta`, ack flag. |
| `ShiftRecord`    | Append-only audit entry for each shift (delta, source block, trigger). Feeds the post-event report. |
| `OutboxEntry`    | Local-only offline write queue row (§6). Never synced; carries a `sequence` causality key. |
| `Template`       | **Not** a `@Model` — a `Codable` value type loaded from bundled JSON; a date-independent event blueprint. |

`PostEventReport` and `WeatherSnapshot` are `Codable` value types stored as
JSON `Data` on `EventModel` and accessed through computed properties.

### 4.2 PersistenceController

`Services/PersistenceController.swift` owns the single `ModelContainer`.

- Store lives in the **App Group container**
  (`group.com.neelsoftwaresolutions.shiftTimeline`) so the widget and extensions
  can read it. `cloudKitDatabase: .none` — the app is fully local-first; no
  iCloud account required.
- Container construction is **defensively staged**: (1) open the existing store
  with the migration plan; (2) on failure, delete and rebuild fresh; (3) last
  resort, an in-memory container. Obj-C `NSException`s thrown by SwiftData's
  migration machinery are caught via the `ObjCException` shim and converted to
  recoverable Swift errors so a migration fault degrades instead of crashing.
- A `forTesting()` factory returns an in-memory container for unit/UI tests.

### 4.3 Schema versioning & migration

The store has evolved through **16 versioned schemas** (`SHIFTSchemaV1…V16`),
orchestrated by `SHIFTMigrationPlan` (a `SchemaMigrationPlan`). **Every stage is
a lightweight migration** — each change only adds optional properties with
defaults, or drops optional properties.

Selected milestones:

| Transition | Change                                                                 |
| ---------- | ---------------------------------------------------------------------- |
| V1→V9      | Incremental feature fields (vendor notifications, weather, per-block location, transit blocks, completion times, voice-memo metadata, invite timestamps). |
| **V10→V11**| **Drops CloudKit-only fields** (`shareURL`, `ownerRecordName`, `lastShiftedAt`, `cloudKitRecordName`) — the CloudKit→Supabase pivot. |
| V11→V12    | Adds `OutboxEntry` — the offline write queue.                          |
| V12→V13    | Adds `OutboxEntry.sequence` — the monotonic FIFO/causality key.        |
| V13→V14    | Adds `updatedAt` to Event/Track/Block/Vendor — the last-write-wins basis. |
| V14→V15    | Adds `VendorModel.profileId`/`acceptedAt` — claim-on-sign-in state.    |
| V15→V16    | Adds `EventModel.ownerId` — owned-vs-shared read-only gating.          |

> **Invariant (documented in the migration plan):** each `VersionedSchema` must
> contain *frozen* `@Model` snapshots, not references to the live model types. If
> two versions reference the same live type their checksums collide and
> `NSLightweightMigrationStage.init` throws — which is exactly the failure the
> `PersistenceController` fallback chain is built to survive.

### 4.4 Repository pattern

Writes flow through five `@MainActor` protocols in
`Services/Repositories`, each with a `SwiftData…Repository` production
implementation and a `Fake…Repository` test double. `RepositoryProviding`
bundles all five for injection; `SwiftDataRepositoryProvider` wires them to one
`ModelContext`, and the Sync layer decorates them (§6) to add cloud mirroring.

Reads deliberately do **not** go through repositories — SwiftUI's `@Query`
observes the store directly so the UI stays live as sync mutates it.

---

## 5. The Timeline Engine

The product's defining capability is **rippling a time change through a
timeline**: move one block and everything downstream adjusts, respecting pinned
anchors and explicit dependencies. This lives in `SHIFTKit/Sources/Engine` as a
**stateless, pure** subsystem.

```
            ┌──────────────────── RippleEngine.recalculate ────────────────────┐
            │                                                                   │
 blocks ───►│  1. DependencyResolver   resolve explicit downstream dependents  │
 changed    │     (BFS over adjacency graph; detects cycles)                   │
 delta      │                                                                   │
            │  2. Bounded propagation  shift the changed block + subsequent     │
            │     Fluid blocks up to the first Pinned wall; union in explicit   │
            │     dependents (which may cross the wall — a user contract)       │
            │                                                                   │
            │  3. CollisionDetector    flag Fluid↔Pinned overlaps (requiresReview)
            │  4. CompressionCalculator resolve overlaps by squeezing durations │
            └──────────────────────────► RippleResult (sorted blocks + status) ─┘
```

Key design points:

- **Pinned blocks are hard walls** for positional ripple — nothing past the
  first downstream pinned block moves by position. **Explicit dependents** (a
  declared `dependsOn` contract) *do* cross the wall.
- **Mutation in place:** `recalculate` mutates `scheduledStart` directly on the
  passed `TimeBlockModel` reference instances so SwiftData change-tracking and
  cloud mirroring pick the changes up automatically. Callers that need undo must
  snapshot first.
- **Determinism & testability:** no I/O, injectable collaborators
  (`DependencyResolver`, `CollisionDetector`, `CompressionCalculator`), and a
  `RippleResult` status enum (`clean`, `pinnedBlockCannotShift`,
  `circularDependency`, …). This is the most heavily unit-tested code in the
  repo.

Every committed shift also writes a `ShiftRecord` (via
`PersistenceController.recordShift`) so the post-event report can reconstruct how
much, and how often, the day drifted.

---

## 6. Sync Architecture (offline-first ⇄ Supabase)

The Sync layer (`shiftTimeline/Sync`) reconciles the local SwiftData store with
Supabase. Its contract: **local writes never block or fail on the network**, and
all devices **converge** to the same state.

### 6.1 Write path — local-first Outbox

```
 UI action
   │
   ▼
 Outbox-decorated repository ──► 1. write to SwiftData (optimistic, succeeds now)
   (OutboxCoordinator)           2. enqueue OutboxEntry { table, rowID, op, payload, sequence }
                                     in the SAME context.save()
   │
   │  (later, when connected)
   ▼
 OutboxFlusher  ── FIFO by `sequence` ──►  SupabaseOutboxSender ──► PostgREST upsert
                                                                    (onConflict: id)
```

- **`OutboxCoordinator`** captures every mutation as an `OutboxEntry`: a
  value-type snapshot (table, row id, operation, JSON payload) stamped with a
  **monotonic `sequence`**. Sequence encodes FK causality — events before
  tracks before blocks before vendors — so a parent is never sent after its
  child. It also catches in-place edits and direct `context.insert`s on
  `save()`, sorting that dirty set parents-first before enqueuing.
- **`OutboxFlusher`** drains the queue in ascending `sequence`, deleting each
  entry on success. It is **single-flight** and **head-of-line-blocking**: the
  first failed send halts the pass, increments `attempts`, and schedules an
  **exponential-backoff retry** (`base · 2^(attempts-1)`, capped at 60s).
  Already-sent entries are already deleted, so a retry resumes cleanly.
- **`SupabaseOutboxSender`** makes every send an **idempotent upsert keyed by
  id** (composite key for junction rows). A re-send after a transient failure —
  or a crash between a successful send and the local delete — converges to the
  same row instead of duplicating it. **Deletes are soft** (`UPDATE … SET
  deleted_at = now()`) so the tombstone propagates to offline devices.
- **`ConnectivityMonitor` / `FlushScheduler`** trigger flushes on reconnect (and
  debounced after local writes).

> An earlier, simpler mechanism — `WriteThroughCoordinator` — mirrors writes
> inline (local-first, failures recorded to diagnostics rather than thrown). The
> Outbox supersedes it for durable offline queueing; both funnel local writes
> through the echo suppressor (§6.4).

### 6.2 Read path — hydration, delta, realtime

Three complementary mechanisms keep the local store fresh:

1. **Initial hydration** (`Hydration/InitialHydrator`): on sign-in, pull all
   RLS-scoped rows and upsert-by-id into SwiftData, wiring relationships after
   all rows exist. Idempotent — re-running updates in place, never duplicates.
2. **Delta reconciliation** (`Offline/DeltaReconciler` + `DeltaSource` +
   `LastPulledStore`): on launch/foreground, pull rows where `updated_at >
   lastPulledAt` (including tombstones), replay them through the same applier as
   realtime, and advance the per-scope watermark. This covers any window where
   Realtime was disconnected.
3. **Realtime** (`Realtime/RealtimeSyncService`): one channel per *active* event
   (`event:<id>`), subscribing to all seven event-scoped tables and merging
   their change streams. Applies live so open `@Query` views update instantly.

### 6.3 Conflict resolution — last-write-wins

`RealtimeChangeApplier` (shared by realtime + delta) applies a remote row only
when `incoming.updated_at > local.updated_at`. Equal versions are skipped
(re-delivery protection). Combined with **planner-authoritative RLS** (only the
owner writes the timeline), owner devices converge on the newest server write
regardless of arrival order. `updatedAt` is server-stamped by a Postgres trigger
(§7.3) and is **never touched by local edits**, so it always reflects the
version a local edit was based on.

### 6.4 Echo suppression

`RealtimeEchoSuppressor` remembers each successful local write (table + id) for
a short window. When that write's own Realtime echo arrives, it is skipped — so
local state isn't re-applied over itself and the UI doesn't flicker.

### 6.5 DTOs & mapping

`Sync/DTOs` holds wire models (`EventDTO`, `TrackDTO`, …) mirroring the Postgres
columns plus server-managed fields (`owner_id`, `created_at`, `updated_at`,
`deleted_at`). `Sync/Mapping` holds **pure** domain↔DTO transforms
(`toDTO`, `makeModel`, `apply(to:)`, relationship linkers). Optional fields use
`encodeIfPresent` so a `nil` is *omitted* rather than sent as `null`, preventing
upserts from clobbering server-managed defaults. `SupabaseCoding` handles the
Postgres `timestamptz` ↔ Swift `Date` wire format.

### 6.6 One-time backfill

For users migrating from the pre-Supabase (CloudKit/local-only) build,
`Sync/Backfill` walks the local graph once after sign-in and enqueues `insert`
outbox entries for every owned row (FK order, junctions last). It runs once per
device (`BackfillCompletionStore` flag); two devices on one account both run but
converge server-side via id-keyed upserts.

---

## 7. Backend (Supabase)

### 7.1 Schema

Postgres tables (one migration file each, append-only, in `supabase/migrations`):

| Table           | Purpose                                                      |
| --------------- | ----------------------------------------------------------- |
| `profiles`      | One row per user, mirrors `auth.users`.                     |
| `events`        | Planner's events; `owner_id` FK.                            |
| `tracks`        | Lanes within an event.                                      |
| `blocks`        | Scheduled blocks; `track_id` + denormalized `event_id`.     |
| `event_vendors` | Per-event collaborators; invite/claim state, ack flag, `pending_shift_delta`. |
| `block_vendors` | Junction: vendor↔block assignment (composite key).          |
| `block_dependencies` | Junction: block ordering contracts (composite key).    |
| `shift_records` | Audit log of shifts.                                        |
| `device_tokens` | APNs tokens per profile (**excluded** from realtime — secret). |

Every table carries `updated_at` and `deleted_at` (soft delete).

### 7.2 Row-Level Security

RLS is the authorization boundary. The pattern is **owner-writes /
collaborator-reads**:

- **Writes** to a timeline are gated on `owner_id = auth.uid()` (directly or via
  the parent event) — the planner is authoritative.
- **Reads** are gated on `can_access_event(event_id)`, a security-definer
  function returning true if the caller owns the event *or* is an accepted
  vendor on it.
- A narrow exception lets a vendor flip only their own
  `has_acknowledged_latest_shift` (validated by `event_vendor_ack_only_changed`
  to ensure no other column changed).

### 7.3 Triggers, RPCs, realtime publication

- **`updated_at` trigger:** a BEFORE-UPDATE trigger bumps `updated_at = now()`
  on every table, so delta pulls (`WHERE updated_at > watermark`) catch all
  changes. This is the server clock behind last-write-wins.
- **`claim_invite()` RPC:** run on sign-in. Matches unclaimed `event_vendors`
  rows against the caller's *verified* `auth.users` phone/email (not the
  writable `profiles` row — anti-impersonation) and stamps
  `profile_id`/`accepted_at`.
- **`normalize_phone_digits()`** canonicalizes phone numbers, mirroring the
  client's `PhoneAuthService` normalization.
- **Realtime publication** includes the seven event-scoped tables; RLS still
  filters what each subscriber actually receives.

### 7.4 Push notifications — `shift-notify` Edge Function

```
 owner shifts a vendor's block
   │  (Outbox upsert sets event_vendors.pending_shift_delta)
   ▼
 AFTER UPDATE trigger (pending_shift_delta changed)
   │  pg_net.http_post
   ▼
 shift-notify (Deno/TS Edge Function)
   ├─ threshold check (per-vendor + global floor)
   ├─ look up device_tokens (service-role, RLS-bypass)
   ├─ APNs background push (content-available: 1) via .p8 JWT (ES256)
   └─ on APNs 410 → soft-delete the stale token
   │
   ▼
 vendor's device wakes → posts a rich LOCAL notification + ack banner
```

The push is silent/background; the **client** composes the user-visible
notification from local data (`VendorShiftNotificationContent`). The function's
APNs auth (`apns.ts`) uses token-based `.p8` JWTs, caching the provider token and
choosing the sandbox/prod host by the token's recorded environment.

---

## 8. App Extensions & Cross-Process Data Sharing

SHIFT runs across four processes that must agree on "what's happening now."

| Surface              | Gets data via                          | Contract type        |
| -------------------- | -------------------------------------- | -------------------- |
| Home Screen widget   | App Group `UserDefaults` (`WidgetDataStore`) | `WidgetSharedData` |
| Live Activity        | `ActivityKit`, reclaimed on launch     | `ShiftActivityAttributes` |
| watchOS app          | `WCSession` application context        | `WatchContext` (→), `WatchCommand` (←) |
| watch complication   | App Group cache (`WatchContextStore`)  | `WatchContext`       |

- The **widget** reads a `WidgetSharedData` snapshot the app writes on live-state
  changes, and uses `Text(date, style: .timer)` so countdowns tick without extra
  timeline reloads. The app also writes the next upcoming event date on
  foreground.
- The **watch** is bridged by `WatchSessionManager` (`WCSessionDelegate`): the
  phone pushes `WatchContext` (active/next block, sunset, live flag); the watch
  sends `WatchCommand`s (`.shift`, `.completeBlock`) back. The complication reads
  a cached context so it renders without a live session.

This sharing is why the SwiftData store lives in the App Group container (§4.2).

---

## 9. Cross-Cutting Concerns

### 9.1 App entry & composition

`shiftTimelineApp` (`@main`) builds the `ModelContainer`, instantiates the
environment `@Observable` services, and injects them into `RootContainerView`.
An `@UIApplicationDelegateAdaptor` handles APNs registration, background shift
pushes, and notification tap/foreground routing. Background sync (auth listener,
device-token registrar, backfill) is wired in `.task` after first render.

### 9.2 Auth

`SupabaseAuthService` owns the session stream, upserts the `profiles` row on
sign-in/restore, and exposes `currentProfile`. **Sign in with Apple** is the
active path; **phone OTP** exists (`PhoneAuthService`) but is gated off
(`FeatureFlags.phoneSignIn`) pending an SMS provider. Sign-in triggers invite
claiming, device-token registration, and the one-time backfill.

### 9.3 Monetization

`SubscriptionManager` (`@Observable`, StoreKit 2) resolves a tri-state
entitlement (`unknown`/`free`/`pro`) and enforces free-tier limits (1 active
event, 15 blocks/event, 2 templates). `PaywallView` is presented from ~8 trigger
contexts (event/block limits, vendor sharing, Live Activity, PDF export, …).

### 9.4 Domain services

`WeatherService` (Apple WeatherKit, coordinate-bucketed + cached on the event),
`SunsetService` (sunrise-sunset.org, cache-first), `TravelTimeService` (an actor
over MapKit directions, feeds `TransitBlockInserter`),
`PostEventReportGenerator` (planned-vs-actual drift → PDF). Each isolates its
I/O edge behind a protocol for testing.

### 9.5 Observability

`SyncDiagnosticsCenter` records every sync/push event (failures, retries, drains)
to both the unified log and an in-app diagnostics screen, and forwards them to
**TelemetryDeck** for the planner→vendor funnel. Remote write failures are
recorded rather than thrown, keeping the local-first guarantee intact while
staying visible.

### 9.6 Concurrency

Swift 6 strict concurrency (Xcode 16+). Views/observable state/persistence are
`@MainActor`; value types crossing task boundaries are `Sendable`; streams use
`AsyncStream`; long-lived tasks cancel on `deinit`.

---

## 10. Build, Configuration & Testing

### 10.1 Configuration

`Config/*.xcconfig` selects environment-specific Supabase URLs/anon keys
(`Debug.xcconfig` → dev, `Release.xcconfig` → prod). Real secrets live in
`Config/Secrets.xcconfig` (gitignored); `Secrets.xcconfig.template` documents the
required keys. Supabase migrations target separate **dev** and **prod** projects
(see `supabase/README.md`), and migration files are **append-only**.

### 10.2 Testing strategy

- **Unit tests** (`shiftTimelineTests`, **Swift Testing** `@Test`/`#expect`):
  each builds a fresh in-memory container; pure logic (ripple engine, go-live /
  exit-live transitions, report generation, sync coordinators with fakes) is
  tested directly. `TestSupport` provides fixture builders and repository fakes.
- **UI tests** (`shiftTimelineUITests`, XCUITest): **page-object** pattern over
  centralized `AccessibilityID`s. The app boots with `-UITestMode` (in-memory
  store), `-ResetData`, `-SeedFixture <name>`, and `-FrozenNow <iso8601>` so
  time-dependent screens are deterministic.
- **Backend tests** (`supabase/tests`): SQL suites covering RLS, the invite
  claim flow, realtime/indexes, storage policies, and the shift-notify trigger.

### 10.3 CI/CD — Xcode Cloud

Workflows are defined canonically as YAML in `.xcode/workflows` (the App Store
Connect GUI is the executor; the YAML is the source of truth):

- **`pr-uitests`** — on every PR to `main`/`develop`: UI tests **sharded across
  4 parallel iPhone 16 simulators** (test plans in `TestPlans/`), target ≤ 8 min.
- **`nightly-full`** — the full suite on a schedule.

`ci_scripts` run as build phases: `ci_post_clone.sh` installs SwiftFormat and
asserts Xcode ≥ 16; `ci_pre_xcodebuild.sh` validates the active test plan exists.

---

## 11. Key Design Decisions & Invariants (summary)

1. **Local-first.** SwiftData is the UI's source of truth; the network is never
   in the user's critical path. Remote failures are recorded, not surfaced as
   errors.
2. **Idempotent convergence.** Every cloud write is an upsert-by-id; every read
   merge is upsert-by-id; re-sends and re-deliveries are safe.
3. **Causal ordering.** Outbox `sequence` guarantees parents sync before
   children; the flusher is FIFO + head-of-line-blocking.
4. **Soft deletes.** Deletes are tombstones (`deleted_at`) so offline devices
   learn about them via delta pulls.
5. **Last-write-wins on a server clock.** A trigger-stamped `updated_at` plus
   owner-authoritative RLS makes conflict resolution deterministic.
6. **Server-verified identity.** Invite claiming matches against `auth.users`,
   never client-writable profile fields.
7. **Pure domain core.** The ripple engine and state transitions are
   deterministic, I/O-free, and exhaustively unit-tested.
8. **Frozen schema snapshots.** Each SwiftData schema version embeds frozen
   model copies; the persistence layer is built to survive a migration fault
   rather than crash.

---

## Appendix A — Subsystem → primary files

| Subsystem            | Entry / primary files                                                            |
| -------------------- | -------------------------------------------------------------------------------- |
| App entry            | `shiftTimeline/shiftTimelineApp.swift`, `Navigation/RootContainerView.swift`     |
| Persistence          | `SHIFTKit/Sources/Services/PersistenceController.swift`                           |
| Schema/migration     | `SHIFTKit/Sources/Models/SHIFTMigrationPlan.swift`, `SHIFTSchemaV1…V16.swift`     |
| Domain models        | `SHIFTKit/Sources/Models/EventModel.swift`, `TimeBlockModel.swift`, …            |
| Ripple engine        | `SHIFTKit/Sources/Engine/RippleEngine.swift`, `DependencyResolver.swift`, …      |
| Repositories         | `SHIFTKit/Sources/Services/Repositories/*Repositing.swift` + `SwiftData*` impls  |
| Outbox write path    | `Sync/Repositories/OutboxCoordinator.swift`, `Sync/Offline/OutboxFlusher.swift`, `SupabaseOutboxSender.swift` |
| Read path            | `Sync/Hydration/InitialHydrator.swift`, `Sync/Offline/DeltaReconciler.swift`     |
| Realtime             | `Sync/Realtime/RealtimeSyncService.swift`, `RealtimeChangeApplier.swift`, `RealtimeEchoSuppressor.swift` |
| DTOs & mapping       | `Sync/DTOs/*DTO.swift`, `Sync/Mapping/*+SupabaseMapping.swift`                    |
| Auth                 | `Auth/SupabaseAuthService.swift`, `Auth/PhoneAuthService.swift`                   |
| Backend schema/RLS   | `supabase/migrations/2026*.sql`                                                   |
| Push function        | `supabase/functions/shift-notify/index.ts`, `apns.ts`                            |
| Widget / Watch       | `shiftTimelineWidget/`, `shiftTimelineWatch Watch App/`, `shiftTimelineWatchWidget/` |
| CI                   | `.xcode/workflows/*.yml`, `ci_scripts/*.sh`                                       |
