#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"

if [ -z "${MESHAGENT_API_URL:-}" ]; then
    echo "MESHAGENT_API_URL must point at the meshagent-server started by the E2E harness." >&2
    exit 1
fi

export RUN_MESHAGENT_LIVE_ASSISTANT_TESTS=1

cd "$ROOT_DIR"
printf 'resolution: workspace\n' > powerboards/pubspec_overrides.yaml
exec "$FLUTTER_BIN" test \
    meshagent-sdk/meshagent-agents-dart/test/live_assistant_thread_test.dart \
    "$@"
