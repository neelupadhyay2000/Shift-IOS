// Pure logic for the one-shot marketplace-launch fan-out (E24 Task 1).
// Kept side-effect-free so `deno test` covers the wave semantics without a
// Supabase or APNs dependency — mirrors shift-notify/notification.ts.

/// Which announcement wave is being sent. Vendors are notified days before
/// planners so the directory has supply before discovery traffic arrives.
export type LaunchWave = "vendor" | "planner";

/// The deep-link role carried in the push payload. 'both'-role waitlisters are
/// sent the *vendor* experience (set up your profile first) — that is the whole
/// point of the stagger.
export type LaunchRole = "vendor" | "planner";

// Must match RemoteShiftPushHandler.marketplaceLaunchKey on iOS.
export const MARKETPLACE_LAUNCH_KEY = "com.shift.marketplaceLaunch";

/// The waitlist interest_role values a wave targets.
///   vendor wave  → vendor + both  (both-members are future supply; seed them first)
///   planner wave → planner only   (both-members were already stamped by wave 1)
export function rolesForWave(wave: LaunchWave): string[] {
  return wave === "vendor" ? ["vendor", "both"] : ["planner"];
}

/// Push copy per wave. Vendor copy drives profile setup; planner copy drives browsing.
export function launchAlert(wave: LaunchWave): { title: string; body: string } {
  if (wave === "vendor") {
    return {
      title: "The Shift Marketplace is live",
      body: "You asked to be first in line — set up your vendor profile now and start getting requests.",
    };
  }
  return {
    title: "The Shift Marketplace is live",
    body: "Find photographers, caterers, DJs and more — browse verified vendors for your next event.",
  };
}

/// The full APNs payload for one wave. The launch key routes the tap:
/// vendor → MyVendorProfileEditorView, planner → Marketplace home.
export function launchPayload(wave: LaunchWave): Record<string, unknown> {
  const alert = launchAlert(wave);
  return {
    aps: { alert, sound: "default" },
    [MARKETPLACE_LAUNCH_KEY]: wave satisfies LaunchRole,
  };
}
