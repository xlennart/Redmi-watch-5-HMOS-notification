// Shared by the real notification extension and the cloud tests.
// Deliberately stores metadata only: no notification text, title, hashes or device IDs.
export class ProbeStats {
  schemaVersion: number = 1;
  received: number = 0;
  ignoredSelf: number = 0;
  cancelCallbacks: number = 0;
  cancelledItems: number = 0;
  lastBundleName: string = '';
  lastReceivedAt: number = 0;
  lastCancelledAt: number = 0;
}

export function safeCounter(value: number): number {
  return Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

function increment(value: number, amount: number): number {
  return Math.min(Number.MAX_SAFE_INTEGER, safeCounter(value) + safeCounter(amount));
}

export function cleanStats(input: ProbeStats): ProbeStats {
  const result = new ProbeStats();
  result.received = safeCounter(input.received);
  result.ignoredSelf = safeCounter(input.ignoredSelf);
  result.cancelCallbacks = safeCounter(input.cancelCallbacks);
  result.cancelledItems = safeCounter(input.cancelledItems);
  result.lastReceivedAt = safeCounter(input.lastReceivedAt);
  result.lastCancelledAt = safeCounter(input.lastCancelledAt);
  result.lastBundleName = typeof input.lastBundleName === 'string' ? input.lastBundleName.slice(0, 256) : '';
  return result;
}

export function decodeStats(text: string): ProbeStats {
  try {
    const parsed = JSON.parse(text) as ProbeStats;
    if (!parsed || typeof parsed !== 'object' || parsed.schemaVersion !== 1) return new ProbeStats();
    return cleanStats(parsed);
  } catch (_) {
    return new ProbeStats();
  }
}

export function receiveNotification(stats: ProbeStats, bundleName: string, ownBundleName: string,
  observedAt: number): ProbeStats {
  const result = cleanStats(stats);
  if (bundleName === ownBundleName) {
    result.ignoredSelf = increment(result.ignoredSelf, 1);
    return result;
  }
  result.received = increment(result.received, 1);
  result.lastBundleName = bundleName.slice(0, 256);
  result.lastReceivedAt = safeCounter(observedAt);
  return result;
}

export function cancelNotifications(stats: ProbeStats, itemCount: number, observedAt: number): ProbeStats {
  const result = cleanStats(stats);
  result.cancelCallbacks = increment(result.cancelCallbacks, 1);
  result.cancelledItems = increment(result.cancelledItems, itemCount);
  result.lastCancelledAt = safeCounter(observedAt);
  return result;
}
