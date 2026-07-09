// Unit tests for the pure launch-wave logic. Run with `deno test`.
import { assertEquals } from "jsr:@std/assert@1";
import { launchAlert, launchPayload, MARKETPLACE_LAUNCH_KEY, rolesForWave } from "./launch.ts";

Deno.test("vendor wave targets vendor + both; planner wave targets planner only", () => {
  // 'both' members must be seeded with the vendor wave and NEVER re-hit by the
  // planner wave — the stagger's core invariant.
  assertEquals(rolesForWave("vendor"), ["vendor", "both"]);
  assertEquals(rolesForWave("planner"), ["planner"]);
});

Deno.test("alert copy differs per wave but shares the launch title", () => {
  const vendor = launchAlert("vendor");
  const planner = launchAlert("planner");
  assertEquals(vendor.title, "The Shift Marketplace is live");
  assertEquals(planner.title, "The Shift Marketplace is live");
  assertEquals(vendor.body.includes("vendor profile"), true);
  assertEquals(planner.body.includes("browse"), true);
});

Deno.test("payload carries the deep-link role under the shared key", () => {
  const vendor = launchPayload("vendor");
  const planner = launchPayload("planner");
  assertEquals(MARKETPLACE_LAUNCH_KEY, "com.shift.marketplaceLaunch");
  assertEquals(vendor[MARKETPLACE_LAUNCH_KEY], "vendor");
  assertEquals(planner[MARKETPLACE_LAUNCH_KEY], "planner");
  // Alert push shape (visible banner + sound).
  const aps = vendor.aps as { alert: { title: string }; sound: string };
  assertEquals(aps.sound, "default");
  assertEquals(aps.alert.title, "The Shift Marketplace is live");
});
