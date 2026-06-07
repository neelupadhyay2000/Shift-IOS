// SHIFT-644: shift-notify Edge Function.
//
// Invoked by the trg_notify_shift_delta trigger (SHIFT-643) when a vendor's
// pending_shift_delta changes. Flow:
//   1. Authoritative threshold check (per-vendor + global floor).
//   2. Resolve the vendor's device tokens (service role bypasses RLS).
//   3. Send exactly one APNs alert per device, choosing host by token environment.
//   4. Soft-delete tokens APNs reports as gone (410) so they stop being targeted.
//
// Secrets (SHIFT-645, set via `supabase secrets set`, never committed):
//   APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY, APNS_BUNDLE_ID
// Platform-injected (do not set): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { shiftBody, type ShiftPayload, shouldNotify } from "./notification.ts";
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

Deno.serve(async (req) => {
  try {
    const payload = (await req.json()) as ShiftPayload;
    if (payload.type !== "shift") {
      return json({ skipped: "ignored_type", type: payload.type }, 200);
    }

    const delta = Number(payload.pending_shift_delta);
    const globalFloor = Number(Deno.env.get("SHIFT_GLOBAL_SHIFT_THRESHOLD_SECONDS") ?? "0");
    if (!shouldNotify(delta, Number(payload.notification_threshold ?? 0), globalFloor)) {
      return json({ skipped: "below_threshold", delta }, 200);
    }

    const apns = loadApnsConfig();
    if (!apns) {
      // SHIFT-645 secrets not set yet — fail loud so it's obvious in logs.
      return json({ error: "APNs secrets missing (APNS_KEY_ID/TEAM_ID/PRIVATE_KEY)" }, 500);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    const { data: tokens, error } = await supabase
      .from("device_tokens")
      .select("apns_token, environment")
      .eq("profile_id", payload.profile_id)
      .is("deleted_at", null);

    if (error) return json({ error: error.message }, 500);
    if (!tokens || tokens.length === 0) return json({ skipped: "no_devices" }, 200);

    const apsPayload = {
      aps: {
        alert: { title: "Schedule updated", body: shiftBody(delta) },
        sound: "default",
        "thread-id": payload.event_id,
      },
      [EVENT_ID_KEY]: payload.event_id,
      pending_shift_delta: delta,
    };

    // One push per device token → "exactly one push per eligible vendor device".
    const results = await Promise.all(
      tokens.map((t) => sendApns(apns, t.apns_token, t.environment, apsPayload)),
    );

    // APNs 410 = token no longer valid → stop targeting it.
    const stale = results.filter((r) => r.status === 410).map((r) => r.token);
    if (stale.length > 0) {
      await supabase
        .from("device_tokens")
        .update({ deleted_at: new Date().toISOString() })
        .in("apns_token", stale);
    }

    const sent = results.filter((r) => r.status === 200).length;
    return json({ sent, total: results.length, results }, 200);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
