// SHIFT-644: pure, testable notification logic for the shift-notify function.
//
// Kept free of I/O so the threshold rule (the acceptance criterion) and the body
// string can be unit-tested with `deno test` without network or env.

export interface ShiftPayload {
  type: string;
  event_vendor_id: string;
  event_id: string;
  profile_id: string;
  pending_shift_delta: number; // seconds (matches VendorModel.pendingShiftDelta: TimeInterval)
  notification_threshold: number; // seconds, per-vendor (event_vendors.notification_threshold)
}

/** Effective threshold = the stricter (higher) of the per-vendor and global floor. */
export function effectiveThresholdSeconds(
  perVendor: number,
  globalFloor: number,
): number {
  return Math.max(perVendor || 0, globalFloor || 0);
}

/**
 * Whether a shift's drift warrants a push. Authoritative, server-side gate for
 * "a shift exceeding threshold triggers a push; sub-threshold shifts don't".
 * Magnitude only — a shift earlier (negative) counts the same as later.
 */
export function shouldNotify(
  deltaSeconds: number,
  perVendorThreshold: number,
  globalFloor: number,
): boolean {
  if (deltaSeconds == null || Number.isNaN(deltaSeconds)) return false;
  const magnitude = Math.abs(deltaSeconds);
  if (magnitude === 0) return false;
  return magnitude >= effectiveThresholdSeconds(perVendorThreshold, globalFloor);
}

/**
 * Alert body, mirroring the first sentence of VendorShiftNotificationContent.body
 * ("Timeline shifted +15 min."). The client (SHIFT-639) enriches with next-block
 * detail on receipt; this is the backgrounded/locked-screen fallback text.
 */
export function shiftBody(deltaSeconds: number): string {
  const minutes = Math.trunc(deltaSeconds / 60);
  const sign = minutes >= 0 ? "+" : "";
  return `Timeline shifted ${sign}${minutes} min.`;
}

export interface AssignmentPayload {
  type: "assignment";
  event_vendor_id: string;
  event_id: string;
  profile_id: string;
  block_title: string;
  /** > 1 for the claim-time catch-up that summarizes pre-claim assignments. */
  block_count?: number;
}

/** Alert body for a vendor newly assigned to one or more blocks. */
export function assignmentBody(blockTitle: string, blockCount = 1): string {
  if (blockCount > 1) return `You've been added to ${blockCount} blocks.`;
  const title = (blockTitle ?? "").trim() || "a block";
  return `You've been added to "${title}".`;
}

export interface GoLivePayload {
  type: "golive";
  event_id: string;
  event_title: string;
}

/** Alert body when an event goes live (title carries the event name). */
export function goLiveBody(): string {
  return "The event is now live — tap to follow the timeline.";
}

// ─────────────────────────────────────────────────────────────────────────────
// Marketplace service requests (E11)
// ─────────────────────────────────────────────────────────────────────────────

export interface RequestReceivedPayload {
  type: "request_received";
  request_id: string;
  vendor_profile_id: string; // recipient (the targeted vendor)
  event_title: string;
}

/** Alert body for a vendor receiving a new service request. */
export function requestReceivedBody(eventTitle: string): string {
  const title = (eventTitle ?? "").trim() || "an event";
  return `New request for ${title}.`;
}

export interface RequestResponsePayload {
  type: "request_response";
  request_id: string;
  planner_id: string; // recipient (the requesting planner)
  vendor_profile_id: string; // responder — its business_name is resolved server-side
  status: string; // "accepted" | "declined"
}

/** Alert body for a planner whose request was accepted/declined. */
export function requestResponseBody(businessName: string, status: string): string {
  const name = (businessName ?? "").trim() || "A vendor";
  const verb = status === "accepted" ? "accepted" : "declined";
  return `${name} ${verb} your request.`;
}

// ─────────────────────────────────────────────────────────────────────────────
// Request chat (E12)
//
// FUTURE WORK: push coalescing for chatty threads is deliberately out of v1 —
// every message currently fires one push. A future iteration can debounce /
// collapse rapid messages per (thread, recipient).
// ─────────────────────────────────────────────────────────────────────────────

export interface RequestMessagePayload {
  type: "request_message";
  request_id: string;
  recipient_id: string; // the OTHER participant (resolved by the trigger)
  sender_id: string; // sender's display name is resolved server-side
  body: string;
}

/** Truncates a chat message for the push body (whole message stays in-app). */
export function truncateMessage(body: string, max = 140): string {
  const trimmed = (body ?? "").trim();
  if (trimmed.length <= max) return trimmed;
  return trimmed.slice(0, max - 1).trimEnd() + "…";
}
