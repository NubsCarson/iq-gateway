// Inflight request deduplication.
// Prevents thundering herd: concurrent requests for the same key share one promise.

// The Map can be typed as Promise<unknown> at the call site so a single map
// can dedupe heterogeneous work; T is inferred from `fn`'s return type.
export function deduped<T>(
  inflight: Map<string, Promise<unknown>>,
  key: string,
  fn: () => Promise<T>,
): Promise<T> {
  const existing = inflight.get(key) as Promise<T> | undefined;
  if (existing) return existing;
  const promise = fn().finally(() => inflight.delete(key));
  inflight.set(key, promise);
  return promise;
}
