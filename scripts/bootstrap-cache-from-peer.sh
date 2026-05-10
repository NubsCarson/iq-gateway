#!/usr/bin/env bash
# Bootstrap a cold gateway's cache by downloading a peer's snapshot.
#
# Modes:
#
#   1. local
#      ./scripts/bootstrap-cache-from-peer.sh <peer-url> <cache-dir>
#      Streams the peer's /cache/snapshot into <cache-dir>. Use before
#      starting the gateway, or restart it afterwards.
#
#   2. k8s
#      ./scripts/bootstrap-cache-from-peer.sh --k8s <peer-url> [namespace] [deployment]
#      Scales the deployment to 0, wipes the cache PVC, untars the
#      peer's snapshot in via a temp pod, scales back up. The full
#      restore flow with no race conditions.
#
# Examples:
#   ./scripts/bootstrap-cache-from-peer.sh https://gateway.solanainternet.com ./cache
#   ./scripts/bootstrap-cache-from-peer.sh --k8s https://gateway.solanainternet.com iqlabs gateway

set -euo pipefail

if [ "${1:-}" = "--k8s" ]; then
  shift
  PEER_URL="${1:-}"
  NS="${2:-iqlabs}"
  DEP="${3:-gateway}"
  if [ -z "$PEER_URL" ]; then
    echo "usage: $0 --k8s <peer-url> [namespace] [deployment]" >&2
    exit 1
  fi
  PEER_URL="${PEER_URL%/}"

  PVC=$(kubectl get deployment "$DEP" -n "$NS" -o jsonpath='{.spec.template.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}' | head -1)
  if [ -z "$PVC" ]; then
    echo "[bootstrap] no PVC found on deployment $NS/$DEP" >&2
    exit 2
  fi

  echo "[bootstrap] peer:        $PEER_URL"
  echo "[bootstrap] namespace:   $NS"
  echo "[bootstrap] deployment:  $DEP"
  echo "[bootstrap] PVC:         $PVC"

  echo "[bootstrap] checking peer is reachable..."
  curl -sSf "$PEER_URL/cache/info" >/dev/null

  REPLICAS=$(kubectl get deployment "$DEP" -n "$NS" -o jsonpath='{.spec.replicas}')
  echo "[bootstrap] scaling $DEP to 0 (was $REPLICAS) so cache.db has no readers..."
  kubectl scale deployment/"$DEP" -n "$NS" --replicas=0
  kubectl wait --for=delete pod -l app="$DEP" -n "$NS" --timeout=60s 2>/dev/null || true

  POD_NAME="cache-bootstrap-$(date +%s)"
  echo "[bootstrap] running temp pod $POD_NAME ..."
  kubectl apply -n "$NS" -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
spec:
  restartPolicy: Never
  containers:
    - name: bootstrap
      image: alpine:3
      command: ["sh", "-c"]
      args:
        - |
          set -e
          apk add --no-cache curl tar sqlite >/dev/null
          echo "wiping /app/cache..."
          rm -rf /app/cache/* 2>/dev/null || true
          rm -rf /app/cache/.[!.]* 2>/dev/null || true
          echo "fetching $PEER_URL/cache/snapshot ..."
          curl -sSf "$PEER_URL/cache/snapshot" | tar -xz -C /app/cache
          echo "row count:"
          sqlite3 /app/cache/cache.db "SELECT COUNT(*) FROM cache_entries"
          du -sh /app/cache
      volumeMounts:
        - name: cache
          mountPath: /app/cache
  volumes:
    - name: cache
      persistentVolumeClaim:
        claimName: $PVC
YAML

  kubectl wait --for=condition=Ready pod/"$POD_NAME" -n "$NS" --timeout=30s 2>/dev/null || true
  kubectl logs -f "$POD_NAME" -n "$NS" --tail=50 || true
  kubectl wait --for=condition=Ready=false pod/"$POD_NAME" -n "$NS" --timeout=300s 2>/dev/null || true
  kubectl delete pod "$POD_NAME" -n "$NS" --ignore-not-found

  echo "[bootstrap] scaling $DEP back up to $REPLICAS..."
  kubectl scale deployment/"$DEP" -n "$NS" --replicas="$REPLICAS"
  kubectl rollout status deployment/"$DEP" -n "$NS" --timeout=120s

  echo "[bootstrap] done."
  exit 0
fi

# Local mode
PEER_URL="${1:-}"
CACHE_DIR="${2:-./cache}"
if [ -z "$PEER_URL" ]; then
  echo "usage: $0 <peer-url> [cache-dir]" >&2
  echo "       $0 --k8s <peer-url> [namespace] [deployment]" >&2
  exit 1
fi
PEER_URL="${PEER_URL%/}"

echo "[bootstrap] peer:      $PEER_URL"
echo "[bootstrap] cache-dir: $CACHE_DIR"

INFO=$(curl -sf "$PEER_URL/cache/info") || { echo "[bootstrap] peer /cache/info failed" >&2; exit 2; }
echo "[bootstrap] peer cache: $INFO"

mkdir -p "$CACHE_DIR"
echo "[bootstrap] downloading + extracting snapshot ..."
curl -sSf "$PEER_URL/cache/snapshot" | tar -xz -C "$CACHE_DIR"

[ -f "$CACHE_DIR/cache.db" ] || { echo "[bootstrap] no cache.db in extracted snapshot" >&2; exit 3; }

ENTRIES=$(sqlite3 "$CACHE_DIR/cache.db" "SELECT COUNT(*) FROM cache_entries" 2>/dev/null || echo "?")
SIZE=$(du -sh "$CACHE_DIR" | cut -f1)
echo "[bootstrap] done. entries=$ENTRIES  size=$SIZE"
echo "[bootstrap] start (or restart) the gateway to pick up the new cache."
