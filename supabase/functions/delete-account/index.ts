// delete-account Edge Function — in-app account deletion (App Store 5.1.1(v)).
//
// Invoked by the iOS client with the caller's JWT. Two steps, both run with
// the service role:
//   1. Remove the caller's voice-memo objects via the Storage API. Hosted
//      Supabase blocks direct SQL deletes on storage tables ("Direct deletion
//      from storage tables is not allowed"), so this cleanup cannot live in a
//      Postgres function.
//   2. auth.admin.deleteUser(): deleting the auth user cascades profiles →
//      owned events → tracks / blocks / event_vendors / junctions /
//      shift_records, and device_tokens via profiles. Vendor links on other
//      planners' events are set null, never deleted.
//
// The caller can only ever delete their own account: the target id comes from
// the verified JWT, never from the request body.
//
// Platform-injected (do not set): SUPABASE_URL, SUPABASE_ANON_KEY,
// SUPABASE_SERVICE_ROLE_KEY.

import { createClient } from "jsr:@supabase/supabase-js@2";

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization) return json({ error: "missing authorization" }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) {
    return json({ error: "missing platform configuration" }, 500);
  }

  // Resolve the caller from their verified JWT.
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) return json({ error: "invalid session" }, 401);

  const admin = createClient(url, serviceKey);

  // 1. Voice memos live at "{event_id}/{block_id}.m4a" under the caller's
  //    owned events; remove them before the cascade orphans the folders.
  const { data: events, error: eventsError } = await admin
    .from("events")
    .select("id")
    .eq("owner_id", user.id);
  if (eventsError) return json({ error: "failed to enumerate events" }, 500);

  for (const event of events ?? []) {
    const { data: files, error: listError } = await admin.storage
      .from("voice-memos")
      .list(event.id);
    if (listError) return json({ error: "failed to list voice memos" }, 500);

    const paths = (files ?? []).map((file) => `${event.id}/${file.name}`);
    if (paths.length > 0) {
      const { error: removeError } = await admin.storage
        .from("voice-memos")
        .remove(paths);
      if (removeError) return json({ error: "failed to remove voice memos" }, 500);
    }
  }

  // 2. Delete the auth user; relational data cascades via foreign keys.
  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) return json({ error: "failed to delete account" }, 500);

  return json({ deleted: true }, 200);
});
