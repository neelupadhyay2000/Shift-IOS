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
}

/** Alert body for a vendor newly assigned to a block. */
export function assignmentBody(blockTitle: string): string {
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
