#!/usr/bin/env bash
# Downloads ggml-base.en.bin into Sources/Narra/Resources/Models/whisper-cpp/
# so the whisper.cpp bundled-offline path works. Idempotent — re-runs as no-ops
# once the file is present and the sha matches.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$ROOT/Sources/Narra/Resources/Models/whisper-cpp"
DEST="$DEST_DIR/ggml-base.en.bin"
URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
EXPECTED_SHA="a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"

mkdir -p "$DEST_DIR"

if [[ -f "$DEST" ]]; then
    actual="$(shasum -a 256 "$DEST" | awk '{print $1}')"
    if [[ "$actual" == "$EXPECTED_SHA" ]]; then
        echo "ggml-base.en.bin already present and verified."
        exit 0
    fi
    echo "Existing model checksum mismatch — re-downloading."
fi

echo "Downloading ggml-base.en.bin (~142 MB)…"
curl -L --fail --progress-bar -o "$DEST" "$URL"

actual="$(shasum -a 256 "$DEST" | awk '{print $1}')"
if [[ "$actual" != "$EXPECTED_SHA" ]]; then
    echo "ERROR: checksum mismatch (expected $EXPECTED_SHA, got $actual)" >&2
    exit 1
fi

echo "Done: $DEST"
