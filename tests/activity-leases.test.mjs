import assert from "node:assert/strict";
import test from "node:test";

test("activity leases become active immediately and expire after their ttl", async () => {
  const { ActivityLeases } = await import("../src/activity-leases.ts");
  const leases = new ActivityLeases(() => 1_000);

  leases.renew("status-popover", 5_000);

  assert.equal(leases.hasActiveLeases(), true);
  assert.deepEqual(leases.snapshot(), {
    active: true,
    leases: [{ name: "status-popover", expiresAt: 6_000 }],
  });

  leases.setNowForTests(() => 6_001);

  assert.equal(leases.hasActiveLeases(), false);
  assert.deepEqual(leases.snapshot(), { active: false, leases: [] });
});

test("activity leases can be released explicitly", async () => {
  const { ActivityLeases } = await import("../src/activity-leases.ts");
  const leases = new ActivityLeases(() => 1_000);

  leases.renew("web-dashboard", 10_000);
  leases.release("web-dashboard");

  assert.equal(leases.hasActiveLeases(), false);
  assert.deepEqual(leases.snapshot(), { active: false, leases: [] });
});
