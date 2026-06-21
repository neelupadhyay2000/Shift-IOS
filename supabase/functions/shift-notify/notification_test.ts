// Unit tests for the pure notification logic. Run with `deno test`.
import { assertEquals } from "jsr:@std/assert@1";
import {
  assignmentBody,
  goLiveBody,
  requestReceivedBody,
  requestResponseBody,
  shiftBody,
  shouldNotify,
} from "./notification.ts";

Deno.test("shouldNotify gates on magnitude vs the stricter threshold", () => {
  assertEquals(shouldNotify(0, 0, 0), false);
  assertEquals(shouldNotify(120, 300, 0), false); // below per-vendor
  assertEquals(shouldNotify(-600, 300, 0), true); // magnitude, earlier counts
  assertEquals(shouldNotify(120, 0, 300), false); // below global floor
});

Deno.test("shiftBody formats signed minutes", () => {
  assertEquals(shiftBody(900), "Timeline shifted +15 min.");
  assertEquals(shiftBody(-600), "Timeline shifted -10 min.");
});

Deno.test("assignmentBody — single vs many", () => {
  assertEquals(assignmentBody("Ceremony"), 'You\'ve been added to "Ceremony".');
  assertEquals(assignmentBody("", 3), "You've been added to 3 blocks.");
});

Deno.test("goLiveBody is constant", () => {
  assertEquals(goLiveBody(), "The event is now live — tap to follow the timeline.");
});

Deno.test("requestReceivedBody includes the event title, with fallback", () => {
  assertEquals(requestReceivedBody("Sarah's Wedding"), "New request for Sarah's Wedding.");
  assertEquals(requestReceivedBody("  "), "New request for an event.");
});

Deno.test("requestResponseBody — accepted/declined with business-name fallback", () => {
  assertEquals(requestResponseBody("Golden Hour", "accepted"), "Golden Hour accepted your request.");
  assertEquals(requestResponseBody("Atlas Sound", "declined"), "Atlas Sound declined your request.");
  assertEquals(requestResponseBody("", "accepted"), "A vendor accepted your request.");
});
