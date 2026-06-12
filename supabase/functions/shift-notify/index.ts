// shift-notify Edge Function — vendor push fan-out.
//
// Invoked by Postgres triggers via pg_net. Branches on payload `type`:
//   - "shift"      (SHIFT-643/644): a vendor's pending_shift_delta changed →
//                  background (content-available) push; the client wakes and
//                  posts a rich local notification (threshold-gated server-side).
//   - "assignment" : a vendor was added to a block (block_vendors INSERT) →
//                  alert push with a server-built title/body (no client render
//                  needed; iOS shows it directly, tap deep-links via EVENT_ID_KEY).
//
// Common to both: resolve the (claimed) vendor's device tokens with the service
// role (bypasses RLS), send one push per device, and soft-delete tokens APNs
// reports gone (410).
//
// Secrets (set via `supabase secrets set`, never committed):
//   APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY, APNS_BUNDLE_ID
// Platform-injected (do not set): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  assignmentBody,
  type AssignmentPayload,
  goLiveBody,
  type GoLivePayload,
  shiftBody,
  type ShiftPayload,
  shouldNotify,
} from "./notification.ts";
import { type ApnsConfig, sendApns } from "./apns.ts";

// Must match VendorShiftNotificationContent.eventIDKey so the tap deep-links (SHIFT-639).
const EVENT_ID_KEY = "com.shift.eventID";

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function loadApnsConfig(): ApnsConfig | null {
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const privateKeyPem = Deno.env.get("APNS_PRIVATE_KEY");
  const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "com.neelsoftwaresolutions.shiftTimeline";
  if (!keyId || !teamId || !privateKeyPem) return null;
  return { keyId, teamId, privateKeyPem, bundleId };
}

function makeSupabase(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
}

// SHIFT-668: durable failure capture. pg_net trigger responses are
// fire-and-forget, so a delivery failure that only lives in this function's
// response is invisible in production. Every failure path writes a row to
// `notification_failures` (service role) — the queryable alert source in the
// launch-readiness runbook. Best-effort by design: alerting must never break
// delivery or mask the original error.
type FailureContext = { kind: string; eventId?: string; profileId?: string };

async function recordFailure(
  supabase: SupabaseClient,
  ctx: FailureContext,
  reason: "secrets_missing" | "token_query_failed" | "apns_rejected" | "exception",
  detail: string,
  apnsStatus?: number,
): Promise<void> {
  try {
    await supabase.from("notification_failures").insert({
      kind: ctx.kind,
      reason,
      detail: detail.slice(0, 1000),
      apns_status: apnsStatus ?? null,
      event_id: ctx.eventId ?? null,
      profile_id: ctx.profileId ?? null,
    });
  } catch (_) {
    // Swallow: never let alerting take down the push path.
  }
}

// Resolve every live device token across the given profiles, send one push each,
// reap 410s. Handles a single recipient (shift/assignment) or a fan-out (go-live).
async function sendToProfiles(
  supabase: SupabaseClient,
  apns: ApnsConfig,
  profileIds: string[],
  apsPayload: unknown,
  options: { pushType: "alert" | "background"; priority: string },
  ctx: FailureContext,
): Promise<Response> {
  if (profileIds.length === 0) return json({ skipped: "no_recipients" }, 200);

  const { data: tokens, error } = await supabase
    .from("device_tokens")
    .select("apns_token, environment")
    .in("profile_id", profileIds)
    .is("deleted_at", null);

  if (error) {
    await recordFailure(supabase, ctx, "token_query_failed", error.message);
    return json({ error: error.message }, 500);
  }
  if (!tokens || tokens.length === 0) return json({ skipped: "no_devices" }, 200);

  // One push per device token → exactly one push per eligible vendor device.
  const results = await Promise.all(
    tokens.map((t) => sendApns(apns, t.apns_token, t.environment, apsPayload, options)),
  );

  // APNs 410 = token no longer valid → stop targeting it.
  const stale = results.filter((r) => r.status === 410).map((r) => r.token);
  if (stale.length > 0) {
    await supabase
      .from("device_tokens")
      .update({ deleted_at: new Date().toISOString() })
      .in("apns_token", stale);
  }

  // Any other non-200 is a real delivery failure — record it for alerting.
  // (410 reaping above is routine token lifecycle, not an outage signal.)
  const rejected = results.filter((r) => r.status !== 200 && r.status !== 410);
  for (const r of rejected) {
    await recordFailure(
      supabase,
      ctx,
      "apns_rejected",
      `${r.reason ?? "apns_error"} token…${r.token.slice(-8)}`,
      r.status,
    );
  }

  const sent = results.filter((r) => r.status === 200).length;
  return json({ sent, total: results.length, results }, 200);
}

async function handleShift(payload: ShiftPayload): Promise<Response> {
  const delta = Number(payload.pending_shift_delta);
  const globalFloor = Number(Deno.env.get("SHIFT_GLOBAL_SHIFT_THRESHOLD_SECONDS") ?? "0");
  if (!shouldNotify(delta, Number(payload.notification_threshold ?? 0), globalFloor)) {
    return json({ skipped: "below_threshold", delta }, 200);
  }

  const ctx: FailureContext = { kind: "shift", eventId: payload.event_id, profileId: payload.profile_id };
  const apns = loadApnsConfig();
  if (!apns) {
    await recordFailure(makeSupabase(), ctx, "secrets_missing", "APNS_KEY_ID/TEAM_ID/PRIVATE_KEY");
    return json({ error: "APNs secrets missing (APNS_KEY_ID/TEAM_ID/PRIVATE_KEY)" }, 500);
  }

  // Alert push (was content-available): iOS throttles silent pushes hard, which
  // made shift notifications flaky. A visible alert at priority 10 is delivered
  // reliably; the in-app ack banner is driven by the synced pending_shift_delta
  // (event_vendors), not by this push, so it still works. Tap deep-links via
  // EVENT_ID_KEY through the existing RemoteShiftPushHandler.
  const apsPayload = {
    aps: { alert: { title: "Timeline shift", body: shiftBody(delta) }, sound: "default" },
    [EVENT_ID_KEY]: payload.event_id,
    event_vendor_id: payload.event_vendor_id,
    pending_shift_delta: delta,
  };
  return await sendToProfiles(makeSupabase(), apns, [payload.profile_id], apsPayload, {
    pushType: "alert",
    priority: "10",
  }, ctx);
}

async function handleAssignment(payload: AssignmentPayload): Promise<Response> {
  // The trigger only forwards claimed vendors; guard defensively anyway.
  if (!payload.profile_id) return json({ skipped: "unclaimed_vendor" }, 200);

  const ctx: FailureContext = { kind: "assignment", eventId: payload.event_id, profileId: payload.profile_id };
  const apns = loadApnsConfig();
  if (!apns) {
    await recordFailure(makeSupabase(), ctx, "secrets_missing", "APNS_KEY_ID/TEAM_ID/PRIVATE_KEY");
    return json({ error: "APNs secrets missing (APNS_KEY_ID/TEAM_ID/PRIVATE_KEY)" }, 500);
  }

  // Alert push: the server already knows the block title, so iOS can show it
  // directly (reliable when backgrounded/locked). EVENT_ID_KEY lets the tap
  // deep-link to the event via the existing RemoteShiftPushHandler.
  const apsPayload = {
    aps: {
      alert: {
        title: "New assignment",
        body: assignmentBody(payload.block_title, payload.block_count ?? 1),
      },
      sound: "default",
    },
    [EVENT_ID_KEY]: payload.event_id,
    event_vendor_id: payload.event_vendor_id,
  };
  return await sendToProfiles(makeSupabase(), apns, [payload.profile_id], apsPayload, {
    pushType: "alert",
    priority: "10",
  }, ctx);
}

async function handleGoLive(payload: GoLivePayload): Promise<Response> {
  const ctx: FailureContext = { kind: "golive", eventId: payload.event_id };
  const apns = loadApnsConfig();
  if (!apns) {
    await recordFailure(makeSupabase(), ctx, "secrets_missing", "APNS_KEY_ID/TEAM_ID/PRIVATE_KEY");
    return json({ error: "APNs secrets missing (APNS_KEY_ID/TEAM_ID/PRIVATE_KEY)" }, 500);
  }

  const supabase = makeSupabase();

  // Fan out to every claimed vendor on the event (one event-going-live → many
  // recipients). Unclaimed vendors have no device and are skipped by the join.
  const { data: vendors, error } = await supabase
    .from("event_vendors")
    .select("profile_id")
    .eq("event_id", payload.event_id)
    .not("profile_id", "is", null)
    .is("deleted_at", null);

  if (error) {
    await recordFailure(supabase, ctx, "token_query_failed", error.message);
    return json({ error: error.message }, 500);
  }
  const profileIds = [...new Set((vendors ?? []).map((v) => v.profile_id as string))];
  if (profileIds.length === 0) return json({ skipped: "no_vendors" }, 200);

  const apsPayload = {
    aps: { alert: { title: payload.event_title, body: goLiveBody() }, sound: "default" },
    [EVENT_ID_KEY]: payload.event_id,
  };
  return await sendToProfiles(supabase, apns, profileIds, apsPayload, {
    pushType: "alert",
    priority: "10",
  }, ctx);
}

Deno.serve(async (req) => {
  let kind = "unknown";
  try {
    const payload = (await req.json()) as { type?: string };
    kind = payload.type ?? "unknown";
    if (payload.type === "shift") return await handleShift(payload as ShiftPayload);
    if (payload.type === "assignment") return await handleAssignment(payload as AssignmentPayload);
    if (payload.type === "golive") return await handleGoLive(payload as GoLivePayload);
    return json({ skipped: "ignored_type", type: payload.type }, 200);
  } catch (e) {
    await recordFailure(makeSupabase(), { kind }, "exception", String(e));
    return json({ error: String(e) }, 500);
  }
});
