#!/usr/bin/env bash
# Build + push the gateway image to GHCR with the right buildx flags.
#
# Why this script: `docker buildx build` defaults to producing an OCI
# image index with provenance + SBOM attestation manifests. That index
# uses media types older container runtimes don't understand, so the
# manifest comes back as 404 to anything that asks for the classic
# Docker manifest v2 format (Akash provider's runtime, for one). The
# fix is `--provenance=false --sbom=false --output=...,oci-mediatypes=false`
# every time. Easier to keep that in one place than re-derive it.
#
# Usage:
#   ./scripts/build-and-push.sh <tag> [<extra-tag> ...]
#
# Example:
#   ./scripts/build-and-push.sh v15 0.2.1 latest

set -euo pipefail

REPO="ghcr.io/iqcoreteam/iq-gateway"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <tag> [<extra-tag> ...]" >&2
  exit 1
fi

TAGS=()
for t in "$@"; do
  TAGS+=("-t" "$REPO:$t")
done

echo "[build] $REPO  tags: $*"
docker buildx build \
  --platform linux/amd64 \
  --provenance=false \
  --sbom=false \
  --output="type=registry,oci-mediatypes=false" \
  "${TAGS[@]}" \
  "$HERE"

echo "[build] verifying public manifest formats..."
TOKEN=$(curl -sf "https://ghcr.io/token?service=ghcr.io&scope=repository:iqcoreteam/iq-gateway:pull" | sed -E 's/.*"token":"([^"]+)".*/\1/')
for accept in \
  "application/vnd.oci.image.index.v1+json" \
  "application/vnd.docker.distribution.manifest.list.v2+json" \
  "application/vnd.docker.distribution.manifest.v2+json"; do
  code=$(curl -sk -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: $accept" \
    "https://ghcr.io/v2/iqcoreteam/iq-gateway/manifests/$1")
  short="${accept##*manifest.}"
  echo "  $short: $code"
done
echo "[build] done."
