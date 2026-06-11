# Ripple Engine — Live-Shift Testing Workflows

> Manual QA scripts for shifting timelines **while an event is live**, built on the
> five bundled templates. Each workflow names a starting template + event start
> time, the exact action to take, and the precise expected result so a tester can
> confirm the ripple engine pass/fail by reading the clock.

This document is the QA companion to the engine described in
[`SHIFTKit/Sources/Engine/RippleEngine.swift`](../SHIFT/SHIFTKit/Sources/Engine/RippleEngine.swift).
The bundled templates live in
[`shiftTimeline/Templates/`](../shiftTimeline/Templates) (mirrored into
`SHIFTKit/Sources/Services/Resources/Templates/`).

---

## 0. How the engine behaves (the rules these workflows verify)

Read this first — every expected result below is a direct consequence of these
seven invariants.

1. **Pinned blocks are hard walls.** A positive shift propagates to the changed
   block and every *subsequent fluid* block **up to, but not past, the first
   downstream pinned block**. The pinned block never moves.
2. **Fully-packed runs absorb forward shifts.** Collision + compression run on
   every commit. When the trapped fluid run already fills the gap before the
   wall, compression closes the gaps right back and the timeline returns to its
   packed layout (status `.clean`) — the shift is effectively absorbed.
3. **Overflow is resolved by proportional compression**, not by pushing the
   wall. A trapped run that overruns the wall is scaled by
   `(block.duration / totalRunDuration) × availableGap`, laid out contiguously
   from the run's (post-shift) start to end exactly at the wall.
4. **Compression respects `minimumDuration` — but templates import with
   `minimumDuration = 0`.** So a freshly-imported template can always compress
   to fit; the `.impossible` / `requiresReview` path **cannot be reached from a
   template alone** — you must manually set minimum durations on the trapped
   blocks first. (See Workflow H.)
5. **Same-start siblings ripple as a unit.** Two fluid blocks sharing the exact
   same `scheduledStart` move together, even though only one was dragged.
6. **Live `+x` extends the active block in place.** In live mode the active
   block's *duration* grows (its start stays put); downstream fluids ripple and
   the trapped run squeezes. If the next wall can't absorb the extension the
   call is **rejected atomically** (`exceedsAvailableSlack`) — nothing moves.
7. **Negative shifts clamp at `originalStart`.** A block can never be dragged
   earlier than where the template originally placed it.

> **Going live:** in each workflow, import the template at the stated start time,
> open the timeline, and tap **Go Live**. This sets the event to `.live`, stamps
> `wentLiveAt`, and marks the first non-completed block `.active`. Planning-mode
> shifts (`applyShift`) and live extensions (`applyExtension`) are different code
> paths — workflows tagged **[LIVE-EXT]** exercise the extension path; the rest
> exercise shift-while-live.

---

## Template reference (block offsets)

All offsets are minutes from event start. **P** = pinned wall.

**Birthday Party** (4 h)

| Block | Start–End | Dur |
|---|---|---|
| Venue Setup & Decorations | 0–45 | 45 |
| Guest Arrival & Welcome | 45–75 | 30 |
| Activities & Games | 75–120 | 45 |
| Food & Drinks | 120–165 | 45 |
| **Cake & Candles (P)** | 165–185 | 20 |
| Gift Opening | 185–215 | 30 |
| Free Play & Photos | 215–230 | 15 |
| Farewell & Goodie Bags | 230–240 | 10 |

> Note the front half (Setup→Food) is **fully packed** — it ends exactly at the
> Cake wall with **zero slack**.

**Concert / Festival** — pinned on *both* sides of the main run

| Block | Start–End | Dur |
|---|---|---|
| Stage & Sound Check | 0–60 | 60 |
| **Gates Open (P)** | 60–90 | 30 |
| Opening DJ Set | 90–135 | 45 |
| MC Welcome & Announcements | 135–150 | 15 |
| Opening Act | 150–195 | 45 |
| Changeover Break | 195–225 | 30 |
| Support Act | 225–270 | 45 |
| Stage Reset | 270–290 | 20 |
| **Headliner Performance (P)** | 290–345 | 55 |
| Encore | 345–360 | 15 |

**Corporate Gala** — *adjacent* pinned pair

| Block | Start–End | Dur |
|---|---|---|
| Venue Final Walk-Through | 0–30 | 30 |
| Guest Registration & Welcome Drinks | 30–75 | 45 |
| **Opening Remarks (P)** | 75–90 | 15 |
| **Keynote Presentation (P)** | 90–135 | 45 |
| Dinner Service | 135–195 | 60 |
| Awards Ceremony | 195–240 | 45 |
| Entertainment / Live Band | 240–270 | 30 |
| Networking & Open Bar | 240–300 | 60 |
| Closing Remarks | 270–285 | 15 |

> Entertainment and Networking **share start offset 240** (same-start siblings).

**Indian Wedding** — same-start sibling portraits + a pinned wall right after

| Block | Start–End | Dur |
|---|---|---|
| … | … | … |
| Bridal Portraits | 150–180 | 30 |
| Groom Portraits | 150–180 | 30 |
| **Baraat Procession (P)** | 180–225 | 45 |
| … | … | … |

> Bridal Portraits and Groom Portraits **share start offset 150**.

---

## Workflow A — Clean downstream ripple (no wall ahead)

**Template:** Birthday Party · **Start:** 10:00 AM · Go Live.

**Action:** Shift **Gift Opening** (13:05) by **+10 min**.

Gift Opening is *after* the only pinned block, so there is no wall ahead — the
ripple is unbounded and clean.

**Expected:**

| Block | Before | After |
|---|---|---|
| Cake & Candles (P) | 12:45 | **12:45** (unchanged — upstream) |
| Gift Opening | 13:05 | **13:15** |
| Free Play & Photos | 13:35 | **13:45** |
| Farewell & Goodie Bags | 13:50 | **14:00** |

✅ Pass: the three downstream fluid blocks all move +10; the pinned Cake block and
everything before it stay put. Status `.clean`.

---

## Workflow B — Wall stops the ripple; packed run absorbs the shift

**Template:** Birthday Party · **Start:** 10:00 AM · Go Live.

**Action:** Shift **Activities & Games** (11:15) by **+20 min**.

This is the counter-intuitive one (rule 2). The shift propagates Activities
(→11:35) and Food & Drinks (→12:20) toward the Cake wall, Food overruns the wall
(12:20+45 = 13:05 > 12:45), and compression then resolves the trapped run. Because
the run [Setup, Guest Arrival, Activities, Food] totals exactly 165 min and the
gap to the wall is exactly 165 min, compression **closes the gaps back to the
original packed layout**.

**Expected (after commit):**

| Block | Before | After |
|---|---|---|
| Venue Setup | 10:00 | **10:00** |
| Guest Arrival | 10:45 | **10:45** |
| Activities & Games | 11:15 | **11:15** (snaps back!) |
| Food & Drinks | 12:00 | **12:00** |
| Cake & Candles (P) | 12:45 | **12:45** |

✅ Pass: net-zero visible movement, status `.clean`. The timeline does **not**
let Food overrun the Cake, and it does **not** move the Cake. (The drag *preview*
will show the overrun-then-compress; the committed result is the packed layout.)

⚠️ If after commit Food & Drinks ends **after** 12:45, or the Cake block moved —
**FAIL** (wall breached).

---

## Workflow C — Visible proportional compression between two walls

**Template:** Concert / Festival · **Start:** 5:00 PM · Go Live.

This is the template that produces a *visible* squeeze, because the main run is
pinned on both ends (Gates Open before it, Headliner after it), so the run's
left edge is anchored and pushing it right genuinely shrinks the available gap.

Block clock times at 17:00 start: Gates Open **18:00 (P)**, Opening DJ **18:30**,
MC **19:15**, Opening Act **19:30**, Changeover **20:15**, Support **20:45**,
Stage Reset **21:30**, Headliner **21:50 (P)**.

**Action:** Shift **Opening DJ Set** (18:30) by **+30 min**.

The run [Opening DJ, MC, Opening Act, Changeover, Support, Stage Reset] totals
**200 min**, but after the first block moves to 19:00 the gap to the Headliner
wall (21:50) is only **170 min**. Compression scales every block by
**170/200 = 0.85**:

| Block | Dur before | Dur after | New start–end |
|---|---|---|---|
| Opening DJ Set | 45 | **38.25** | 19:00 – 19:38¼ |
| MC Welcome | 15 | **12.75** | 19:38¼ – 19:51 |
| Opening Act | 45 | **38.25** | 19:51 – 20:29¼ |
| Changeover Break | 30 | **25.5** | 20:29¼ – 20:54¾ |
| Support Act | 45 | **38.25** | 20:54¾ – 21:33 |
| Stage Reset | 20 | **17** | 21:33 – 21:50 |
| **Headliner (P)** | 55 | 55 | **21:50** – 22:45 |

✅ Pass: all six fluid blocks shrink proportionally, the run ends **exactly** at
21:50, the Headliner is untouched, status `.clean`. (Stage & Sound Check and
Gates Open, both upstream of the dragged block, do not move.)

⚠️ FAIL if any block keeps its full duration and pushes Headliner later, or if the
run ends before/after 21:50.

---

## Workflow D — Negative shift clamps at originalStart

**Template:** Birthday Party · **Start:** 10:00 AM · Go Live.

**Action (two steps):**
1. Shift **Gift Opening** (13:05) by **+30 min** → it moves to **13:35** (clean,
   downstream ripple as in Workflow A; Free Play→14:05, Farewell→14:20).
2. Now shift **Gift Opening** by **−60 min**.

`originalStart` for Gift Opening is its import position, **13:05**. The negative
shift target is 13:35 − 60 = 12:35, but the clamp is
`max(originalStart, target) = max(13:05, 12:35) = 13:05`.

**Expected after step 2:**

| Block | After +30 | After −60 |
|---|---|---|
| Gift Opening | 13:35 | **13:05** (clamped — not 12:35) |
| Free Play & Photos | 14:05 | **13:35** |
| Farewell & Goodie Bags | 14:20 | **13:50** |

✅ Pass: Gift Opening lands back on **13:05**, never earlier than its original
slot, even though −60 mathematically wanted 12:35.

⚠️ FAIL if Gift Opening lands at 12:35 (clamp ignored).

---

## Workflow E — Same-start siblings move together

**Template:** Indian Wedding · **Start:** 9:00 AM · Go Live.

Bridal Portraits and Groom Portraits both sit at offset 150 → **11:30**. Baraat
Procession is pinned at offset 180 → **12:00**.

**Action:** Shift **Bridal Portraits** (11:30) by **+10 min**.

Rule 5: the sibling Groom Portraits shares the exact start, so it ripples too.
Both become 11:40 (dur 30 → end 12:10), overrunning the Baraat wall (12:00) by
10 min, so compression closes the run back to fit before 12:00.

**Expected:**

| Block | Before | After |
|---|---|---|
| Bridal Portraits | 11:30 | **moves with sibling, compressed to end ≤ 12:00** |
| Groom Portraits | 11:30 | **moves with sibling, compressed to end ≤ 12:00** |
| Baraat Procession (P) | 12:00 | **12:00** (unchanged) |

✅ Pass: **both** portrait blocks respond to dragging only one of them, and
neither overruns the Baraat wall.

⚠️ FAIL if Groom Portraits stays at 11:30 while Bridal moves (sibling left
behind — the classic ripple bug), or if either ends after 12:00.

---

## Workflow F — Adjacent pinned pair (double wall)

**Template:** Corporate Gala · **Start:** 6:00 PM · Go Live.

Opening Remarks **19:15 (P)** and Keynote **19:30 (P)** are back-to-back walls.

**Action:** Shift **Guest Registration & Welcome Drinks** (18:30) by **+15 min**.

Registration (dur 45) moves to 18:45 → ends 19:30, overrunning Opening Remarks
(19:15). The trapped run before the first wall is [Venue Walk, Registration],
total 75 min, gap to the wall = 19:15 − 18:00 = 75 min → compression closes it
back to the packed layout (Venue 18:00–18:30, Registration 18:30–19:15).

**Expected:**

| Block | Before | After |
|---|---|---|
| Venue Final Walk-Through | 18:00 | **18:00** |
| Guest Registration | 18:30 | **18:30** (snaps back, packed) |
| Opening Remarks (P) | 19:15 | **19:15** |
| Keynote (P) | 19:30 | **19:30** |

✅ Pass: **both** pinned blocks hold their slots and the gap between them (the
15-min Opening Remarks) is never compressed — pinned durations are immovable.

⚠️ FAIL if either pinned block shifts, or if the Opening-Remarks→Keynote gap
changes.

---

## Workflow G — [LIVE-EXT] Extending the active block, and atomic rejection

**Template:** Birthday Party · **Start:** 10:00 AM · Go Live, then mark blocks
complete until **Activities & Games** is the **active** block (start 11:15).

Live `+x` extends the *active* block's duration in place (rule 6). Next fluid is
Food & Drinks (12:00, dur 45), then the Cake wall (12:45). Available slack =
`wall.start − fluidRun.start − Σmin = 12:45 − 12:00 − 0 = 45 min`.

**Action 1 — within slack:** Extend Activities by **+20 min**.

| Block | Before | After |
|---|---|---|
| Activities & Games (active) | 11:15, dur 45 | 11:15, **dur 65** (ends 12:20) |
| Food & Drinks | 12:00, dur 45 | shifts +20 → 12:20, **squeezed to end 12:45** (dur 25) |
| Cake & Candles (P) | 12:45 | **12:45** |

✅ Pass: the active block grows (start unchanged), Food squeezes against the
wall, Cake holds, status `.hasCollisions` (resolved).

**Action 2 — exceeds slack (do this fresh, or undo Action 1 first):** Extend
Activities by **+50 min** (> 45 max).

✅ Pass: call is **rejected atomically** — status `.exceedsAvailableSlack`,
**nothing moves at all**. The UI should surface "can extend up to 45 min."

**Action 3 — zero-slack block:** mark forward until **Food & Drinks** is active
(it sits directly against the Cake wall, slack = 12:45 − 12:45 = **0**). Any
`+x` extension → immediately `.exceedsAvailableSlack`, no mutation.

⚠️ FAIL if a rejected extension partially moves any block, or if the active
block's *start* changes instead of its duration.

---

## Workflow H — Reaching `.impossible` / requiresReview (needs manual minimums)

**Why it needs setup:** templates import with `minimumDuration = 0`, so the
trapped run can always shrink to fit and `.impossible` is unreachable from a
template alone (rule 4). To test the review path you must first give the trapped
blocks a floor.

**Template:** Concert / Festival · **Start:** 5:00 PM · Go Live.

**Setup:** On the main run [Opening DJ, MC, Opening Act, Changeover, Support,
Stage Reset], set each block's **minimum duration to its full current duration**
(45/15/45/30/45/20 → Σ = 200 min). Now the run cannot shrink below 200 min, but
the gap to the Headliner is only ~170 min after a forward shift.

**Action:** Repeat Workflow C — shift **Opening DJ Set** by **+30 min**.

**Expected:**

- Compression cannot fit 200 min of minimums into the 170-min gap.
- All trapped blocks are parked at their `minimumDuration`, **`requiresReview`
  is set true** on each, status `.impossible`.
- The UI should flag the run for review rather than silently overrunning.

✅ Pass: blocks flagged for review, Headliner still at 21:50, status
`.impossible`.

⚠️ FAIL if a block shrinks below its minimum, or if the Headliner wall moves to
make room.

---

## Quick coverage matrix

| Workflow | Template | Invariant exercised |
|---|---|---|
| A | Birthday | Clean unbounded downstream ripple |
| B | Birthday | Wall stops ripple; packed run absorbs forward shift |
| C | Concert | Visible proportional compression between two walls |
| D | Birthday | Negative-shift clamp at `originalStart` |
| E | Indian Wedding | Same-start siblings ripple together |
| F | Corporate Gala | Adjacent pinned pair both hold |
| G | Birthday | Live `+x` in-place extend + atomic slack rejection |
| H | Concert | `.impossible` / requiresReview (with manual minimums) |

---

## Regression checklist (run after any engine change)

- [ ] A pinned block **never** changes its `scheduledStart` from a fluid shift.
- [ ] No fluid block's end is ever **after** a downstream pinned block's start
      post-commit.
- [ ] Same-start siblings always move as a unit (Workflow E).
- [ ] Negative shifts never cross `originalStart` (Workflow D).
- [ ] Live extension rejections are atomic — zero partial mutation (Workflow G).
- [ ] Committed timeline matches the confirmed drag *preview* exactly (preview
      and commit share the shift→collision→compression pipeline).
