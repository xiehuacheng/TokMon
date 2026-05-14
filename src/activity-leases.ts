export interface ActivityLeaseSnapshot {
  active: boolean;
  leases: Array<{ name: string; expiresAt: number }>;
}

export class ActivityLeases {
  private leases = new Map<string, number>();

  constructor(private now: () => number = Date.now) {}

  renew(name: string, ttlMs: number) {
    const leaseName = name.trim();
    if (!leaseName) return;
    this.leases.set(leaseName, this.now() + Math.max(1_000, ttlMs));
  }

  release(name: string) {
    this.leases.delete(name.trim());
  }

  hasActiveLeases() {
    this.pruneExpired();
    return this.leases.size > 0;
  }

  snapshot(): ActivityLeaseSnapshot {
    this.pruneExpired();
    return {
      active: this.leases.size > 0,
      leases: Array.from(this.leases.entries())
        .map(([name, expiresAt]) => ({ name, expiresAt }))
        .sort((a, b) => a.name.localeCompare(b.name)),
    };
  }

  setNowForTests(now: () => number) {
    this.now = now;
  }

  private pruneExpired() {
    const now = this.now();
    for (const [name, expiresAt] of this.leases.entries()) {
      if (expiresAt <= now) this.leases.delete(name);
    }
  }
}
