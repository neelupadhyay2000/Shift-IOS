// SHIFT-644: unit tests for the pure threshold + body logic.
// Run: deno test supabase/functions/shift-notify/notification_test.ts

import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import { effectiveThresholdSeconds, shiftBody, shouldNotify } from "./notification.ts";

Deno.test("effective threshold takes the higher of per-vendor and global floor", () => {
  assertEquals(effectiveThresholdSeconds(300, 60), 300);
  assertEquals(effectiveThresholdSeconds(0, 120), 120);
  assertEquals(effectiveThresholdSeconds(0, 0), 0);
});

Deno.test("notifies when |delta| meets the effective threshold", () => {
  assert(shouldNotify(900, 300, 60)); // 15 min >= 5 min
  assert(shouldNotify(-600, 300, 0)); // earlier shift counts too
  assert(shouldNotify(300, 300, 0)); // exactly at threshold
});

Deno.test("suppresses sub-threshold shifts", () => {
  assertFalse(shouldNotify(120, 300, 0)); // 2 min < 5 min per-vendor
  assertFalse(shouldNotify(30, 0, 60)); // below global floor
  assertFalse(shouldNotify(0, 0, 0)); // no drift
});

Deno.test("body mirrors the client's first sentence", () => {
  assertEquals(shiftBody(900), "Timeline shifted +15 min.");
  assertEquals(shiftBody(-600), "Timeline shifted -10 min.");
  assertEquals(shiftBody(0), "Timeline shifted +0 min.");
});
