-- ─────────────────────────────────────────────────────────────────────────────
-- Community Templates — official seed content (E23)
--
-- NOT a migration. This is data, it depends on an auth user existing, and it is
-- meant to be run once per project by hand. Keep it out of supabase/migrations.
--
-- WHY A DIRECT INSERT AND NOT publish_community_template():
--   That RPC stamps author_id = auth.uid() and raises 28000 when it is null.
--   A service-role / SQL-editor connection has no auth.uid(), so the RPC cannot
--   be used here. No table has FORCE ROW LEVEL SECURITY, so the owner connection
--   the SQL editor uses bypasses RLS and can INSERT directly.
--
-- HONESTY CONTRACT — read before editing:
--   Two independent flags, and they mean different things.
--
--   `is_official` = TRUE here. An authorship claim: SHIFT wrote this. True, so we
--   assert it. Renders as an "Official" badge.
--
--   `source_event_completed` = FALSE here, always. A provenance claim: this
--   run-sheet came from an event someone actually ran to completion in Shift.
--   These are sample run-sheets, not records of real events, so the claim is
--   false and the badge stays off. Do not flip this column. If you want a
--   verified template, run a real event to completion and publish it from the app
--   with p_source_event_id set — the RPC checks the event is completed and yours,
--   then stamps the badge itself. That one is earned.
--
--   `times_applied` = 0, the column default. It counts real applies, bumped only
--   by apply_community_template. The UI hides the counter at zero, so seeded
--   templates simply show no apply count rather than a fabricated one.
--
--   The same reasoning is why there is no vendor or review seed script. Vendor
--   listings and reviews are reputation, not artifacts: faking them contradicts
--   the App Store description ("a profile can't be faked"), and fabricated
--   reviews violate the FTC's consumer-review rule (16 CFR Part 465) and the
--   Competition Act. Templates are safe to seed because a run-sheet does not
--   claim to be a person.
--
-- PREREQUISITE — create the official author first:
--   Dashboard → Authentication → Users → "Add user"
--     email:    templates@shifttimeline.app
--     password: (anything; nobody signs in with it)
--     ✅ Auto Confirm User
--   No mailbox is needed. This script then creates the matching profiles row with
--   display_name 'SHIFT', which is what `search_community_templates` surfaces as
--   `author_name` (business_name → display_name → 'Shift Member').
--
-- HOW TO RUN:
--   Dashboard → SQL Editor → paste → Run. Idempotent: re-running inserts nothing
--   new (matched on author_id + name), so it is safe against dev and prod both.
--
-- TO UNPUBLISH ONE LATER (never hard-delete; the app soft-deletes):
--   update public.community_templates set deleted_at = now()
--    where author_id = (select id from auth.users
--                        where lower(email) = 'templates@shifttimeline.app')
--      and name = '<template name>';
-- ─────────────────────────────────────────────────────────────────────────────

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Resolve the official author and ensure its profile row exists.
--    Fails loudly rather than silently seeding under the wrong account.
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare
    v_author uuid;
begin
    select id into v_author
      from auth.users
     where lower(email) = 'templates@shifttimeline.app';

    if v_author is null then
        raise exception
            'Official author not found. Create templates@shifttimeline.app in '
            'Dashboard → Authentication → Users → Add user (Auto Confirm), then re-run.'
            using errcode = 'P0002';
    end if;

    -- account_type 'planner' leaves business_name null, so author_name resolves
    -- to display_name. onboarded = true keeps it out of the onboarding gate if
    -- anyone ever does sign in. The founding-comp BEFORE INSERT trigger will
    -- stamp comped_until here; harmless on an account nobody uses.
    insert into public.profiles (id, display_name, email, account_type, onboarded)
    values (v_author, 'SHIFT', 'templates@shifttimeline.app', 'planner', true)
    on conflict (id) do update
        set display_name = 'SHIFT',
            onboarded    = true;
end
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. The templates.
--
--    `blocks` is the iOS [TemplateBlock] array, byte-for-byte:
--        { title, relativeStartOffset, duration, isPinned, colorTag, icon }
--    Offsets and durations are SECONDS from the event start, so a template stays
--    date-independent. isPinned marks the immovable anchors — the moments a
--    planner cannot slide when the day runs late (a ceremony start, a keynote,
--    doors opening, golden hour). Everything else is fluid and the Ripple Engine
--    compresses it. Getting the pins right is what makes a template worth using.
--
--    block_count is derived, never typed, so it cannot drift from `blocks`.
--    Category must be one of: wedding | corporate | social | photography.
-- ─────────────────────────────────────────────────────────────────────────────
with author as (
    select id from auth.users where lower(email) = 'templates@shifttimeline.app'
),
seed (name, description, category, blocks) as (
values
-- ── 1 ────────────────────────────────────────────────────────────────────────
(
    'South Asian Wedding — Baraat to Reception'::text,
    'A full-day North Indian wedding, prep through last dance. The baraat, the '
    'ceremony and the grand entrance are pinned: the procession is timed to the '
    'venue''s street permit and the phere to the muhurat. Everything between them '
    'absorbs the delay.'::text,
    'wedding'::text,
    '[
      {"title":"Groom Prep & Sehra Bandi","relativeStartOffset":0,"duration":3600,"isPinned":false,"colorTag":"#AF52DE","icon":"sparkles"},
      {"title":"Bride Prep & Detail Shots","relativeStartOffset":3600,"duration":5400,"isPinned":false,"colorTag":"#FF2D55","icon":"camera.fill"},
      {"title":"Baraat Procession (Dhol & Horse)","relativeStartOffset":9000,"duration":2700,"isPinned":true,"colorTag":"#FF9500","icon":"music.note"},
      {"title":"Milni & Jaimala","relativeStartOffset":11700,"duration":1800,"isPinned":false,"colorTag":"#FFCC00","icon":"heart.fill"},
      {"title":"Ceremony — Phere","relativeStartOffset":13500,"duration":5400,"isPinned":true,"colorTag":"#5856D6","icon":"book.closed.fill"},
      {"title":"Vidaai & Family Portraits","relativeStartOffset":18900,"duration":2700,"isPinned":false,"colorTag":"#FF2D55","icon":"camera.fill"},
      {"title":"Guest Turnaround & Cocktail Hour","relativeStartOffset":21600,"duration":5400,"isPinned":false,"colorTag":"#34C759","icon":"cup.and.saucer.fill"},
      {"title":"Grand Entrance","relativeStartOffset":27000,"duration":900,"isPinned":true,"colorTag":"#FF3B30","icon":"sparkles"},
      {"title":"First Dance","relativeStartOffset":27900,"duration":600,"isPinned":false,"colorTag":"#AF52DE","icon":"music.note"},
      {"title":"Speeches & Toasts","relativeStartOffset":28500,"duration":2400,"isPinned":false,"colorTag":"#007AFF","icon":"mic.fill"},
      {"title":"Dinner Service","relativeStartOffset":30900,"duration":4500,"isPinned":false,"colorTag":"#FF9500","icon":"fork.knife"},
      {"title":"Cake & Anniversary Dance","relativeStartOffset":35400,"duration":1200,"isPinned":false,"colorTag":"#FFCC00","icon":"gift.fill"},
      {"title":"Open Dance Floor","relativeStartOffset":36600,"duration":10800,"isPinned":false,"colorTag":"#5856D6","icon":"music.note"},
      {"title":"Send-Off","relativeStartOffset":47400,"duration":900,"isPinned":false,"colorTag":"#FF2D55","icon":"heart.fill"}
    ]'::jsonb
),
-- ── 2 ────────────────────────────────────────────────────────────────────────
(
    'Golden Hour Micro-Wedding',
    'Twenty guests, one venue, no turnaround. Built around two fixed points: the '
    'ceremony and the golden-hour couple session. Sunset does not move, so pin it '
    'and let dinner compress instead.',
    'wedding',
    '[
      {"title":"Vendor Load-In & Site Setup","relativeStartOffset":0,"duration":3600,"isPinned":false,"colorTag":"#34C759","icon":"shippingbox.fill"},
      {"title":"Couple Prep & Detail Shots","relativeStartOffset":3600,"duration":3600,"isPinned":false,"colorTag":"#FF2D55","icon":"camera.fill"},
      {"title":"Guest Arrival & Welcome Drinks","relativeStartOffset":7200,"duration":1800,"isPinned":false,"colorTag":"#FFCC00","icon":"cup.and.saucer.fill"},
      {"title":"Ceremony","relativeStartOffset":9000,"duration":1200,"isPinned":true,"colorTag":"#5856D6","icon":"heart.fill"},
      {"title":"Congratulations & Champagne","relativeStartOffset":10200,"duration":1200,"isPinned":false,"colorTag":"#FF9500","icon":"sparkles"},
      {"title":"Family & Party Portraits","relativeStartOffset":11400,"duration":1800,"isPinned":false,"colorTag":"#FF2D55","icon":"person.3.fill"},
      {"title":"Seated Dinner","relativeStartOffset":13200,"duration":5400,"isPinned":false,"colorTag":"#FF9500","icon":"fork.knife"},
      {"title":"Golden Hour Couple Session","relativeStartOffset":18600,"duration":2400,"isPinned":true,"colorTag":"#FFCC00","icon":"sun.max.fill"},
      {"title":"Toasts & Cake","relativeStartOffset":21000,"duration":1800,"isPinned":false,"colorTag":"#007AFF","icon":"mic.fill"},
      {"title":"First Dance & Open Floor","relativeStartOffset":22800,"duration":7200,"isPinned":false,"colorTag":"#AF52DE","icon":"music.note"},
      {"title":"Sparkler Send-Off","relativeStartOffset":30000,"duration":900,"isPinned":false,"colorTag":"#FF3B30","icon":"sparkles"}
    ]'::jsonb
),
-- ── 3 ────────────────────────────────────────────────────────────────────────
(
    'Product Launch — Press Preview & Demo Day',
    'Crew call to load-out for a hardware or software reveal. Doors, the keynote '
    'and the embargo lift are pinned — the embargo is a contractual timestamp, not '
    'a preference. Rehearsal is the block that gives when setup runs long.',
    'corporate',
    '[
      {"title":"Crew Call & AV Load-In","relativeStartOffset":0,"duration":5400,"isPinned":false,"colorTag":"#34C759","icon":"wrench.and.screwdriver.fill"},
      {"title":"Stage & Lighting Check","relativeStartOffset":5400,"duration":3600,"isPinned":false,"colorTag":"#5AC8FA","icon":"lightbulb.fill"},
      {"title":"Speaker Rehearsal & Run-Through","relativeStartOffset":9000,"duration":3600,"isPinned":false,"colorTag":"#007AFF","icon":"mic.fill"},
      {"title":"Press Check-In & Coffee","relativeStartOffset":12600,"duration":2700,"isPinned":false,"colorTag":"#FF9500","icon":"cup.and.saucer.fill"},
      {"title":"Doors Open","relativeStartOffset":15300,"duration":900,"isPinned":true,"colorTag":"#FFCC00","icon":"person.3.fill"},
      {"title":"Keynote — Product Reveal","relativeStartOffset":16200,"duration":2700,"isPinned":true,"colorTag":"#FF3B30","icon":"megaphone.fill"},
      {"title":"Live Demo Stations","relativeStartOffset":18900,"duration":3600,"isPinned":false,"colorTag":"#5856D6","icon":"sparkles"},
      {"title":"Press Q&A / Media Scrum","relativeStartOffset":22500,"duration":1800,"isPinned":false,"colorTag":"#007AFF","icon":"mic.fill"},
      {"title":"Embargo Lifts — Assets Go Live","relativeStartOffset":24300,"duration":300,"isPinned":true,"colorTag":"#AF52DE","icon":"checkmark.seal.fill"},
      {"title":"Analyst Briefings (1:1)","relativeStartOffset":24600,"duration":3600,"isPinned":false,"colorTag":"#34C759","icon":"person.3.fill"},
      {"title":"Networking Reception","relativeStartOffset":28200,"duration":5400,"isPinned":false,"colorTag":"#FF9500","icon":"fork.knife"},
      {"title":"Strike & Load-Out","relativeStartOffset":33600,"duration":5400,"isPinned":false,"colorTag":"#5AC8FA","icon":"shippingbox.fill"}
    ]'::jsonb
),
-- ── 4 ────────────────────────────────────────────────────────────────────────
(
    'Trade Show Exhibit Day — Booth Operations',
    'One day on the floor, from booth build to Day 2 reset. Hall hours and the '
    'theater demo slots are pinned because the venue owns them. Staff rotation and '
    'the VIP walkthrough are what flex.',
    'corporate',
    '[
      {"title":"Booth Build & Tech Check","relativeStartOffset":0,"duration":7200,"isPinned":false,"colorTag":"#34C759","icon":"wrench.and.screwdriver.fill"},
      {"title":"Staff Briefing & Lead Scanner Sync","relativeStartOffset":7200,"duration":1800,"isPinned":false,"colorTag":"#007AFF","icon":"person.3.fill"},
      {"title":"Hall Opens — Morning Traffic","relativeStartOffset":9000,"duration":10800,"isPinned":true,"colorTag":"#FFCC00","icon":"person.3.fill"},
      {"title":"Theater Demo — Slot 1","relativeStartOffset":19800,"duration":1200,"isPinned":true,"colorTag":"#FF3B30","icon":"megaphone.fill"},
      {"title":"Staff Rotation & Lunch","relativeStartOffset":21000,"duration":3600,"isPinned":false,"colorTag":"#FF9500","icon":"fork.knife"},
      {"title":"Afternoon Floor Traffic","relativeStartOffset":24600,"duration":9000,"isPinned":false,"colorTag":"#5856D6","icon":"person.3.fill"},
      {"title":"Theater Demo — Slot 2","relativeStartOffset":33600,"duration":1200,"isPinned":true,"colorTag":"#FF3B30","icon":"megaphone.fill"},
      {"title":"VIP Buyer Walkthrough","relativeStartOffset":34800,"duration":2700,"isPinned":false,"colorTag":"#AF52DE","icon":"star.fill"},
      {"title":"Hall Closes — Lead Export","relativeStartOffset":37500,"duration":1800,"isPinned":false,"colorTag":"#007AFF","icon":"checkmark.seal.fill"},
      {"title":"Booth Reset for Day 2","relativeStartOffset":39300,"duration":3600,"isPinned":false,"colorTag":"#5AC8FA","icon":"shippingbox.fill"}
    ]'::jsonb
),
-- ── 5 ────────────────────────────────────────────────────────────────────────
(
    'Bar & Bat Mitzvah — Service and Celebration',
    'Two venues, one day, a room flip in the middle. The service is pinned to the '
    'synagogue''s schedule and the hora to the band''s downbeat. The turnaround '
    'window is where a late morning gets absorbed.',
    'social',
    '[
      {"title":"Vendor Load-In & Room Flip","relativeStartOffset":0,"duration":5400,"isPinned":false,"colorTag":"#34C759","icon":"shippingbox.fill"},
      {"title":"Family Photos at Synagogue","relativeStartOffset":5400,"duration":2700,"isPinned":false,"colorTag":"#FF2D55","icon":"camera.fill"},
      {"title":"Service & Torah Reading","relativeStartOffset":8100,"duration":5400,"isPinned":true,"colorTag":"#5856D6","icon":"book.closed.fill"},
      {"title":"Kiddush Luncheon","relativeStartOffset":13500,"duration":3600,"isPinned":false,"colorTag":"#FF9500","icon":"fork.knife"},
      {"title":"Guest Turnaround & Party Setup","relativeStartOffset":17100,"duration":5400,"isPinned":false,"colorTag":"#5AC8FA","icon":"wrench.and.screwdriver.fill"},
      {"title":"Cocktail Hour & Kids Games","relativeStartOffset":22500,"duration":3600,"isPinned":false,"colorTag":"#FFCC00","icon":"cup.and.saucer.fill"},
      {"title":"Grand Entrance & Hora","relativeStartOffset":26100,"duration":1800,"isPinned":true,"colorTag":"#FF3B30","icon":"music.note"},
      {"title":"Candle Lighting Ceremony","relativeStartOffset":27900,"duration":1800,"isPinned":false,"colorTag":"#AF52DE","icon":"flame.fill"},
      {"title":"Dinner Service","relativeStartOffset":29700,"duration":4500,"isPinned":false,"colorTag":"#FF9500","icon":"fork.knife"},
      {"title":"Montage Video & Speeches","relativeStartOffset":34200,"duration":1800,"isPinned":false,"colorTag":"#007AFF","icon":"video.fill"},
      {"title":"Open Dance Floor & DJ Set","relativeStartOffset":36000,"duration":7200,"isPinned":false,"colorTag":"#5856D6","icon":"music.note"},
      {"title":"Dessert & Send-Off","relativeStartOffset":43200,"duration":1800,"isPinned":false,"colorTag":"#FF2D55","icon":"gift.fill"}
    ]'::jsonb
),
-- ── 6 ────────────────────────────────────────────────────────────────────────
(
    'Charity Gala & Live Auction',
    'A fundraising dinner where the run-sheet is the revenue plan. Registration, '
    'the mission moment and the live auction are pinned — you do not move the '
    'paddle raise, because the room''s attention peaks once and the auctioneer '
    'knows when. Dessert and entertainment are the shock absorbers.',
    'social',
    '[
      {"title":"Venue Setup & AV Check","relativeStartOffset":0,"duration":7200,"isPinned":false,"colorTag":"#34C759","icon":"wrench.and.screwdriver.fill"},
      {"title":"Auction Item Staging & Bid Sheets","relativeStartOffset":7200,"duration":3600,"isPinned":false,"colorTag":"#FFCC00","icon":"dollarsign.circle.fill"},
      {"title":"Volunteer Briefing","relativeStartOffset":10800,"duration":1800,"isPinned":false,"colorTag":"#007AFF","icon":"person.3.fill"},
      {"title":"Registration & Silent Auction Opens","relativeStartOffset":12600,"duration":5400,"isPinned":true,"colorTag":"#5AC8FA","icon":"person.3.fill"},
      {"title":"Cocktail Reception","relativeStartOffset":18000,"duration":3600,"isPinned":false,"colorTag":"#FF9500","icon":"cup.and.saucer.fill"},
      {"title":"Seated Dinner — First Courses","relativeStartOffset":21600,"duration":3600,"isPinned":false,"colorTag":"#FF9500","icon":"fork.knife"},
      {"title":"Mission Moment & Honoree Speech","relativeStartOffset":25200,"duration":1200,"isPinned":true,"colorTag":"#AF52DE","icon":"heart.fill"},
      {"title":"Live Auction","relativeStartOffset":26400,"duration":2700,"isPinned":true,"colorTag":"#FF3B30","icon":"dollarsign.circle.fill"},
      {"title":"Fund-a-Need Paddle Raise","relativeStartOffset":29100,"duration":1200,"isPinned":false,"colorTag":"#FFCC00","icon":"star.fill"},
      {"title":"Dessert & Entertainment","relativeStartOffset":30300,"duration":2700,"isPinned":false,"colorTag":"#5856D6","icon":"music.note"},
      {"title":"Silent Auction Closes — Checkout","relativeStartOffset":33000,"duration":3600,"isPinned":false,"colorTag":"#007AFF","icon":"checkmark.seal.fill"},
      {"title":"Strike & Item Pickup","relativeStartOffset":36600,"duration":3600,"isPinned":false,"colorTag":"#5AC8FA","icon":"shippingbox.fill"}
    ]'::jsonb
),
-- ── 7 ────────────────────────────────────────────────────────────────────────
(
    'Wedding Photographer — 10-Hour Coverage',
    'The same wedding day, seen from behind the camera. Written for the shooter, '
    'not the planner: the first look, the ceremony, the grand entrance and golden '
    'hour are pinned, and family formals are the block that always overruns. Hand '
    'this to a second shooter and they know the day cold.',
    'photography',
    '[
      {"title":"Gear Check & Travel to Prep","relativeStartOffset":0,"duration":1800,"isPinned":false,"colorTag":"#5AC8FA","icon":"camera.fill"},
      {"title":"Detail Shots — Rings, Dress, Invites","relativeStartOffset":1800,"duration":2700,"isPinned":false,"colorTag":"#FF2D55","icon":"photo.fill"},
      {"title":"Getting Ready — Partner A","relativeStartOffset":4500,"duration":3600,"isPinned":false,"colorTag":"#FF9500","icon":"camera.fill"},
      {"title":"Getting Ready — Partner B","relativeStartOffset":8100,"duration":2700,"isPinned":false,"colorTag":"#FFCC00","icon":"camera.fill"},
      {"title":"First Look","relativeStartOffset":10800,"duration":1800,"isPinned":true,"colorTag":"#AF52DE","icon":"heart.fill"},
      {"title":"Wedding Party Portraits","relativeStartOffset":12600,"duration":2700,"isPinned":false,"colorTag":"#5856D6","icon":"person.3.fill"},
      {"title":"Travel & Ceremony Setup Shots","relativeStartOffset":15300,"duration":1800,"isPinned":false,"colorTag":"#34C759","icon":"car.fill"},
      {"title":"Ceremony","relativeStartOffset":17100,"duration":2700,"isPinned":true,"colorTag":"#FF3B30","icon":"heart.fill"},
      {"title":"Family Formals — Shot List","relativeStartOffset":19800,"duration":2700,"isPinned":false,"colorTag":"#007AFF","icon":"person.3.fill"},
      {"title":"Couple Session","relativeStartOffset":22500,"duration":2700,"isPinned":false,"colorTag":"#FF2D55","icon":"camera.fill"},
      {"title":"Reception Details & Room Shots","relativeStartOffset":25200,"duration":1800,"isPinned":false,"colorTag":"#FFCC00","icon":"photo.fill"},
      {"title":"Grand Entrance & First Dance","relativeStartOffset":27000,"duration":1800,"isPinned":true,"colorTag":"#AF52DE","icon":"music.note"},
      {"title":"Vendor Meal","relativeStartOffset":28800,"duration":1800,"isPinned":false,"colorTag":"#FF9500","icon":"fork.knife"},
      {"title":"Speeches & Cake","relativeStartOffset":30600,"duration":2700,"isPinned":false,"colorTag":"#007AFF","icon":"mic.fill"},
      {"title":"Golden Hour Session","relativeStartOffset":33300,"duration":1800,"isPinned":true,"colorTag":"#FFCC00","icon":"sun.max.fill"},
      {"title":"Open Dancing & Candids","relativeStartOffset":35100,"duration":5400,"isPinned":false,"colorTag":"#5856D6","icon":"music.note"},
      {"title":"Send-Off & Card Backup","relativeStartOffset":40500,"duration":1800,"isPinned":false,"colorTag":"#34C759","icon":"checkmark.seal.fill"}
    ]'::jsonb
)
)
insert into public.community_templates
    (author_id, name, description, category, blocks, block_count,
     source_event_completed, is_official, is_published)
select
    a.id,
    s.name,
    s.description,
    s.category,
    s.blocks,
    jsonb_array_length(s.blocks),   -- derived, so it can never drift
    false,                          -- NOT verified — never run. See the contract above.
    true,                           -- IS official — SHIFT authored it. True, so we say it.
    true
  from seed s
 cross join author a
 where not exists (
        select 1
          from public.community_templates ct
         where ct.author_id = a.id
           and ct.name      = s.name
 );

commit;

-- ─────────────────────────────────────────────────────────────────────────────
-- Verify — 7 rows, every one official = true, verified = false, applied = 0:
--
--   select name, category, block_count, is_official, source_event_completed, times_applied
--     from public.community_templates
--    where author_id = (select id from auth.users
--                        where lower(email) = 'templates@shifttimeline.app')
--    order by category, name;
--
-- And through the read path the app actually uses (author_name must be 'SHIFT'):
--
--   select name, author_name, block_count, is_official, source_event_completed
--     from public.search_community_templates(p_sort => 'newest', p_limit => 20);
-- ─────────────────────────────────────────────────────────────────────────────
