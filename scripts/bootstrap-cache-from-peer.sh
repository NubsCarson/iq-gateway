#!/usr/bin/env bash
# Bootstrap a cold gateway's cache by downloading a peer's snapshot.
#
# Usage:
#   ./scripts/bootstrap-cache-from-peer.sh <peer-url> [cache-dir]
#
# Examples:
#   # local dev:
#   ./scripts/bootstrap-cache-from-peer.sh https://gateway.solanainternet.com ./cache
#
#   # k8s deployment (run on a host with kubectl, against a pod with the
#   # cache PVC mounted at /app/cache):
#   POD=$(kubectl get pods -n iqlabs -l app=gateway -o jsonpath='{.items[0].metadata.name}')
#   kubectl exec -n iqlabs $POD -- bash -c \
#     "cd /app/cache && curl -sS https://gateway.solanainternet.com/cache/snapshot | tar -xz"
#   kubectl rollout restart deployment/gateway -n iqlabs
#
# Reads /cache/snapshot from <peer-url> and untars into <cache-dir>.
# Stop the gateway first (or restart after) so it picks up the new
# cache.db on next boot.

set -euo pipefail

PEER_URL="${1:-}"
CACHE_DIR="${2:-./cache}"

if [ -z "$PEER_URL" ]; then
  echo "usage: $0 <peer-url> [cache-dir]" >&2
  exit 1
fi
PEER_URL="${PEER_URL%/}"

echo "[bootstrap] peer:      $PEER_URL"
echo "[bootstrap] cache-dir: $CACHE_DIR"

# Confirm peer is reachable + show its cache stats
INFO=$(curl -sf "$PEER_URL/cache/info") || {
  echo "[bootstrap] peer /cache/info failed" >&2
  exit 2
}
echo "[bootstrap] peer cache: $INFO"

mkdir -p "$CACHE_DIR"

# Stream the snapshot into tar -xz directly. No tarball file on disk.
echo "[bootstrap] downloading + extracting snapshot ..."
curl -sSf "$PEER_URL/cache/snapshot" | tar -xz -C "$CACHE_DIR"

if [ ! -f "$CACHE_DIR/cache.db" ]; then
  echo "[bootstrap] no cache.db in extracted snapshot — peer may be empty?" >&2
  exit 3
fi

# Quick sanity check: count entries the recipient just received.
ENTRIES=$(sqlite3 "$CACHE_DIR/cache.db" "SELECT COUNT(*) FROM cache_entries" 2>/dev/null || echo "?")
SIZE=$(du -sh "$CACHE_DIR" | cut -f1)
echo "[bootstrap] done. entries=$ENTRIES  size=$SIZE"
echo "[bootstrap] start (or restart) the gateway to pick up the new cache."
