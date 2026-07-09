// marketplace-launch-notify Edge Function — ONE-SHOT launch announcement (E24 Task 1).
//
// Fans out "The Shift Marketplace is live" to marketplace_waitlist members'
// devices, in two admin-triggered waves:
//
//   curl -X POST https://<ref>.supabase.co/functions/v1/marketplace-launch-notify \
//     -H "Authorization: Bearer $SERVICE_ROLE_KEY" -H "content-type: application/json" \
//     -d '{"wave":"vendor","dry_run":true}'      # count recipients, send nothing
//     -d '{"wave":"vendor"}'                     # launch day −N: seed supply
//     -d '{"wave":"planner"}'                    # launch day: open discovery
//
// Idempotent by design: only rows with launch_notified_at IS NULL are targeted,
// and the stamp is written after a successful send — re-running a wave resumes
// where it stopped instead of double-pushing. 'both'-role members are stamped
// by the vendor wave, so the planner wave can never hit them twice.
//
// NOT trigger-invoked (unlike shift-notify): this is an admin blast. The handler
// hard-requires the service-role key as the bearer — a leaked anon key or user
// JWT cannot fire it.
//
// Secrets: same APNs set as shift-notify (APNS_KEY_ID/TEAM_ID/PRIVATE_KEY/BUNDLE_ID).

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { type ApnsConfig, sendApns } from "../shift-notify/apns.ts";
import { launchPayload, type LaunchWave, rolesForWave } from "./launch.ts";

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

// Durable failure capture, same sink as shift-notify (SHIFT-668).
async function recordFailure(
  supabase: SupabaseClient,
  reason: string,
  detail: string,
  profileId?: string,
): Promise<void> {
  try {
    await supabase.from("notification_failures").insert({
      kind: "marketplace_launch",
      reason,
      detail: detail.slice(0, 1000),
      profile_id: profileId ?? null,
    });
  } catch (_) {
    // Never let alerting break the blast.
  }
}

Deno.serve(async (req) => {
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  // Admin gate: platform JWT verification admits any valid JWT (anon included);
  // the real gate is bearer == service role key.
  const bearer = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!serviceKey || bearer !== serviceKey) {
    return json({ error: "service role required" }, 401);
  }

  let wave: LaunchWave;
  let dryRun: boolean;
  let limit: number;
  try {
    const body = (await req.json()) as { wave?: string; dry_run?: boolean; limit?: number };
    if (body.wave !== "vendor" && body.wave !== "planner") {
      return json({ error: "wave must be 'vendor' or 'planner'" }, 400);
    }
    wave = body.wave;
    dryRun = body.dry_run === true;
    // Per-invocation ceiling; also a canary lever ({"wave":"vendor","limit":10}).
    limit = Math.min(Math.max(body.limit ?? 5000, 1), 5000);
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }

  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", serviceKey);

  // Un-notified, live members of this wave's role set.
  const { data: members, error: waitlistError } = await supabase
    .from("marketplace_waitlist")
    .select("profile_id, interest_role")
    .in("interest_role", rolesForWave(wave))
    .is("launch_notified_at", null)
    .is("deleted_at", null)
    .order("created_at", { ascending: true })
    .limit(limit);

  if (waitlistError) {
    await recordFailure(supabase, "token_query_failed", `waitlist: ${waitlistError.message}`);
    return json({ error: waitlistError.message }, 500);
  }
  const profileIds = [...new Set((members ?? []).map((m) => m.profile_id as string))];
  if (profileIds.length === 0) return json({ wave, skipped: "no_unnotified_members" }, 200);

  // Their live device tokens.
  const { data: tokens, error: tokenError } = await supabase
    .from("device_tokens")
    .select("profile_id, apns_token, environment")
    .in("profile_id", profileIds)
    .is("deleted_at", null);

  if (tokenError) {
    await recordFailure(supabase, "token_query_failed", `device_tokens: ${tokenError.message}`);
    return json({ error: tokenError.message }, 500);
  }

  const deviceCount = (tokens ?? []).length;
  const reachable = new Set((tokens ?? []).map((t) => t.profile_id as string));
  if (dryRun) {
    return json({
      wave,
      dry_run: true,
      members: profileIds.length,
      reachable_members: reachable.size,
      devices: deviceCount,
    }, 200);
  }

  const apns = loadApnsConfig();
  if (!apns) {
    await recordFailure(supabase, "secrets_missing", "APNS_KEY_ID/TEAM_ID/PRIVATE_KEY");
    return json({ error: "APNs secrets missing" }, 500);
  }

  // One push per device; sequential-ish batching keeps memory flat for big waves.
  const apsPayload = launchPayload(wave);
  const succeededProfiles = new Set<string>();
  const staleTokens: string[] = [];
  let sent = 0;
  let rejected = 0;

  const BATCH = 50;
  for (let i = 0; i < (tokens ?? []).length; i += BATCH) {
    const batch = (tokens ?? []).slice(i, i + BATCH);
    const results = await Promise.all(batch.map(async (t) => ({
      profileId: t.profile_id as string,
      result: await sendApns(apns, t.apns_token, t.environment, apsPayload, {
        pushType: "alert",
        priority: "10",
      }),
    })));

    for (const { profileId, result } of results) {
      if (result.status === 200) {
        sent += 1;
        succeededProfiles.add(profileId);
      } else if (result.status === 410) {
        staleTokens.push(result.token);
      } else {
        rejected += 1;
        await recordFailure(
          supabase,
          "apns_rejected",
          `${result.reason ?? "apns_error"} status=${result.status} token…${result.token.slice(-8)}`,
          profileId,
        );
      }
    }
  }

  // Reap tokens APNs says are gone (routine lifecycle, not an outage signal).
  if (staleTokens.length > 0) {
    await supabase
      .from("device_tokens")
      .update({ deleted_at: new Date().toISOString() })
      .in("apns_token", staleTokens);
  }

  // Stamp every member who received ≥1 successful push. Members with no live
  // device (or all-failed sends) stay NULL and are retried by a re-run.
  const stamped = [...succeededProfiles];
  if (stamped.length > 0) {
    const { error: stampError } = await supabase
      .from("marketplace_waitlist")
      .update({ launch_notified_at: new Date().toISOString() })
      .in("profile_id", stamped);
    if (stampError) {
      // Sends went out but the stamp failed — surface loudly: a blind re-run
      // would double-push these members.
      await recordFailure(supabase, "exception", `stamp failed: ${stampError.message}`);
      return json({
        wave, sent, rejected,
        stamped: 0,
        error: `pushes sent but stamping failed: ${stampError.message}`,
      }, 500);
    }
  }

  return json({
    wave,
    members: profileIds.length,
    reachable_members: reachable.size,
    devices: deviceCount,
    sent,
    rejected,
    stale_reaped: staleTokens.length,
    stamped: stamped.length,
  }, 200);
});
