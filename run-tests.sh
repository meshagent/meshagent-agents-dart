#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PYTHON_BIN="$ROOT_DIR/.venv/bin/python"
SETUP_SERVER=true
TEST_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --skip-server-setup) SETUP_SERVER=false ;;
        *) TEST_ARGS+=("$arg") ;;
    esac
done

if $SETUP_SERVER; then
    if [ ! -x "$PYTHON_BIN" ]; then
        echo "Expected repo Python environment at $PYTHON_BIN. Set up .venv before running meshagent-agents-dart tests." >&2
        exit 1
    fi

    export PYTHONPATH="$ROOT_DIR/meshagent-sdk/meshagent-api:$ROOT_DIR/meshagent-sdk/meshagent-agents:$ROOT_DIR/meshagent-sdk/meshagent-tools:$ROOT_DIR/meshagent-sdk/meshagent-openai:$ROOT_DIR/meshagent-sdk/meshagent-anthropic:$ROOT_DIR/meshagent-sdk/meshagent-llm-proxy:$ROOT_DIR/meshagent-sdk/meshagent-otel:$ROOT_DIR/meshagent-cloud:$ROOT_DIR/meshagent-server${PYTHONPATH:+:$PYTHONPATH}"

    ROOM_INTERNAL_API_PORT=$("$PYTHON_BIN" -c "from meshagent.api.room_ports import ROOM_INTERNAL_API_PORT; print(ROOM_INTERNAL_API_PORT)")

    export MESHAGENT_API_URL="http://localhost:${ROOM_INTERNAL_API_PORT}"
    export MESHAGENT_SECRET="test-secret-secure-secret-sample2560binarykey"
    export MESHAGENT_PROJECT_ID="testproject"
    export MESHAGENT_KEY_ID="test-key-secure-key-sample2560binarykey"
    export MESHAGENT_SERVER_CLI_FILES_STORAGE_PATH=".local_server_documents"
    unset MESHAGENT_API_KEY

    "$PYTHON_BIN" "$ROOT_DIR/meshagent-server/meshagent/server/cli/cli.py" &
    CLI_PID=$!
    trap 'kill $CLI_PID 2>/dev/null || true' EXIT

    SERVER_READY=false
    for _ in $(seq 1 60); do
        if curl -fsS "$MESHAGENT_API_URL/" >/dev/null; then
            SERVER_READY=true
            break
        fi

        if ! kill -0 $CLI_PID 2>/dev/null; then
            wait $CLI_PID
            echo "MeshAgent test server exited during startup." >&2
            exit 1
        fi

        sleep 0.5
    done

    if ! $SERVER_READY; then
        echo "MeshAgent test server did not become ready at $MESHAGENT_API_URL." >&2
        exit 1
    fi
fi

cd "$ROOT_DIR"
if [ ${#TEST_ARGS[@]} -eq 0 ]; then
    flutter test meshagent-sdk/meshagent-agents-dart/test
else
    flutter test meshagent-sdk/meshagent-agents-dart/test "${TEST_ARGS[@]}"
fi
