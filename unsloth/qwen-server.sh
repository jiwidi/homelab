#!/usr/bin/env bash
# Start Unsloth's llama-server for Qwen3.6-35B-A3B (Apple Silicon / Metal).
# Usage: ./qwen-server.sh [on|off|budget=N]
#
# WHY THIS MODEL (M4 base, 32GB, ~120 GB/s memory bandwidth):
#   This machine is memory-bandwidth-bound, not compute-bound. Generation speed
#   is set by how many bytes must be read per token, so it scales with ACTIVE
#   parameters, not total parameters.
#     Qwen3.8-27B dense  Q4_K_M  -> 17.1GB read/token -> measured ~5 tok/s
#     Qwen3.6-35B-A3B    Q4_K_XL -> ~3B active        -> ~6-8x faster
#   The dense 27B is the better model per-token but is unusably slow for
#   continuous agents here. Revisit if a Qwen3.8 MoE (A3B-class) ships.
#
# WHY THE CONTEXT IS CHEAP:
#   Qwen3.6-35B-A3B is a hybrid-attention MoE: only 10 of 40 layers use full
#   attention (full_attention_interval=4), and those have just 2 KV heads.
#   KV cost is ~10.6 KiB/token at q8_0, so the FULL native 256k context is
#   only ~2.9GB. Context is not the binding constraint here -- weights are.
#
# MEMORY BUDGET (~26GB target of 32GB total):
#   weights ~22.4GB + KV ~2.9GB @256k + Metal compute ~1.5GB = ~26.8GB
#   Docker Desktop is capped at 12GB (uses ~1.5GB idle); keep it that way or
#   this will start swapping.
#
# Tunables (env vars):
#   CTX_OVERRIDE=131072  smaller context = less KV RAM (256k costs only ~2.9GB)
#   KV_TYPE=q4_0         KV quant: q8_0 (default, best quality) or q4_0 (half RAM)
#   HOST_BIND=127.0.0.1  override the default LAN/VPN bind
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Unsloth ships its own prebuilt llama.cpp. Use it, NOT ../llama-cpp/llama.cpp --
# that build is pinned to April 2026 and predates these model architectures.
LLAMA_SERVER="$HOME/.unsloth/llama.cpp/build/bin/llama-server"

MODEL="$SCRIPT_DIR/models/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf"
MMPROJ="$SCRIPT_DIR/models/Qwen3.6-35B-A3B-GGUF/mmproj-F32.gguf"
ALIAS="unsloth/Qwen3.6-35B-A3B"
CTX_SIZE="${CTX_OVERRIDE:-262144}"   # native max; KV is only ~2.9GB at q8_0
KV_TYPE="${KV_TYPE:-q8_0}"
PORT=8001

# Bind to all interfaces so LAN devices and the Twingate connector (which runs
# in host network mode) can reach it. Protected by an API key from .env below.
HOST_BIND="${HOST_BIND:-0.0.0.0}"

THINKING_ARG="${1:-on}"

DOWNLOAD_HINT="cd $SCRIPT_DIR/models && HF_TOKEN=<your-token> uv run --with huggingface_hub hf download unsloth/Qwen3.6-35B-A3B-GGUF --local-dir ./Qwen3.6-35B-A3B-GGUF --include '*UD-Q4_K_XL*' --include '*mmproj-F32*'"

# API key: required, since we bind beyond localhost. Generate one into .env with:
#   echo "LLM_API_KEY=$(openssl rand -hex 24)" > unsloth/.env
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a; . "$SCRIPT_DIR/.env"; set +a
fi
if [ -z "$LLM_API_KEY" ] && [ "$HOST_BIND" != "127.0.0.1" ]; then
    echo "Error: binding to $HOST_BIND with no API key set."
    echo "  Create one with:  echo \"LLM_API_KEY=\$(openssl rand -hex 24)\" > $SCRIPT_DIR/.env"
    echo "  Or bind locally:  HOST_BIND=127.0.0.1 $0 $*"
    exit 1
fi
API_KEY_FLAG=""
if [ -n "$LLM_API_KEY" ]; then
    API_KEY_FLAG="--api-key $LLM_API_KEY"
fi

# Sampling per the Unsloth Qwen3.6 guide. Note these differ from Qwen3.8, which
# wants temp=1.0 for thinking -- do not copy these across model families.
#   Thinking:     temp=0.6, top_p=0.95, top_k=20, min_p=0.0, presence=0.0
#   Non-thinking: temp=0.7, top_p=0.80, top_k=20, min_p=0.0, presence=1.5
TOP_K=20
MIN_P=0.0
REPEAT_PENALTY=1.0
case "$THINKING_ARG" in
  off)
    THINKING_FLAGS="--reasoning off"
    THINKING_DESC="disabled (non-thinking general params)"
    TEMP=0.7; TOP_P=0.8; PRESENCE_PENALTY=1.5
    ;;
  budget=*)
    BUDGET="${THINKING_ARG#budget=}"
    THINKING_FLAGS="--reasoning on --reasoning-budget $BUDGET"
    THINKING_DESC="budget=${BUDGET} tokens (hard cap)"
    TEMP=0.6; TOP_P=0.95; PRESENCE_PENALTY=0.0
    ;;
  on|*)
    THINKING_FLAGS="--reasoning on --reasoning-budget -1"
    THINKING_DESC="enabled, unlimited"
    TEMP=0.6; TOP_P=0.95; PRESENCE_PENALTY=0.0
    ;;
esac

if [ ! -f "$LLAMA_SERVER" ]; then
    echo "Error: Unsloth's llama-server not found at $LLAMA_SERVER"
    echo "Install it with: unsloth studio   (it bundles a prebuilt llama.cpp)"
    exit 1
fi

if [ ! -f "$MODEL" ]; then
    echo "Error: Model not found at $MODEL"
    echo "Download it with:"
    echo "  $DOWNLOAD_HINT"
    exit 1
fi

# mmproj enables vision; optional for text-only agent use.
MMPROJ_FLAG=""
if [ -f "$MMPROJ" ]; then
    MMPROJ_FLAG="--mmproj $MMPROJ"
else
    echo "Note: mmproj not found -- vision disabled."
fi

LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || echo '<lan-ip>')"

echo "==> Starting Qwen3.6-35B-A3B on $HOST_BIND:$PORT"
echo "    Context: $CTX_SIZE (KV quant: $KV_TYPE)"
echo "    Thinking: $THINKING_DESC"
echo "    Sampling: temp=$TEMP top_p=$TOP_P top_k=$TOP_K presence_penalty=$PRESENCE_PENALTY"
echo ""
echo "    Local:    http://127.0.0.1:$PORT/v1"
echo "    LAN:      http://$LAN_IP:$PORT/v1"
echo "    Twingate: add a Resource pointing at $LAN_IP:$PORT"
if [ -n "$LLM_API_KEY" ]; then
    echo "    Auth:     Authorization: Bearer \$LLM_API_KEY  (see unsloth/.env)"
fi
echo ""

exec "$LLAMA_SERVER" \
    --model "$MODEL" \
    $MMPROJ_FLAG \
    --alias "$ALIAS" \
    --temp "$TEMP" \
    --top-p "$TOP_P" \
    --top-k "$TOP_K" \
    --min-p "$MIN_P" \
    --presence-penalty "$PRESENCE_PENALTY" \
    --repeat-penalty "$REPEAT_PENALTY" \
    --port "$PORT" \
    --host "$HOST_BIND" \
    --batch-size 2048 \
    --ubatch-size 512 \
    --parallel 1 \
    --kv-unified \
    --cache-type-k "$KV_TYPE" --cache-type-v "$KV_TYPE" \
    --flash-attn on \
    --ctx-size "$CTX_SIZE" \
    --jinja \
    $API_KEY_FLAG \
    $THINKING_FLAGS
