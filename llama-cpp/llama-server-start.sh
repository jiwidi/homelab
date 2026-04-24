#!/usr/bin/env bash
# Start llama-server for Claude Code integration (Apple Silicon / Metal)
# Usage: ./llama-server-start.sh [27b|35b] [on|off|budget=N]
#
# Default: 27b (Qwen3.6-27B dense) with thinking ON — smaller RAM footprint than
# the 35B-A3B MoE, leaving more room for KV cache on a 32GB machine. Thinking
# defaults ON per Unsloth "precise coding" recommendation.
#
# Thinking modes (maps to llama-server --reasoning / --reasoning-budget, which
# are server-enforced hard limits — unlike chat-template-kwargs thinking_budget
# which is only a model-side hint):
#   on          — thinking enabled, no token limit         (precise-coding params)
#   off         — thinking disabled                        (non-thinking params)
#   budget=512  — thinking HARD-capped at N tokens         (precise-coding params)
#
# Sampling params (per Unsloth Qwen3.6 guide):
#   Thinking + precise coding: temp=0.6, top_p=0.95, top_k=20, min_p=0.0,
#                              presence_penalty=0.0, repeat_penalty=1.0
#   Non-thinking general:      temp=0.7, top_p=0.8,  top_k=20, min_p=0.0,
#                              presence_penalty=1.5, repeat_penalty=1.0
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LLAMA_SERVER="$SCRIPT_DIR/llama.cpp/llama-server"
MODEL_ARG="${1:-27b}"
THINKING_ARG="${2:-on}"   # default on: Unsloth recommends thinking for precise coding

case "$MODEL_ARG" in
  27b)
    # Dense 27B — smaller RAM footprint (~15GB Q4) than the 35B-A3B MoE (~20GB),
    # leaves more for KV cache on a 32GB machine. Default.
    MODEL="$SCRIPT_DIR/models/Qwen3.6-27B-GGUF/Qwen3.6-27B-UD-Q4_K_XL.gguf"
    MMPROJ="$SCRIPT_DIR/models/Qwen3.6-27B-GGUF/mmproj-F16.gguf"
    ALIAS="unsloth/Qwen3.6-27B"
    CTX_SIZE=65536   # dense model — KV grows per token, cap lower to leave headroom
    DOWNLOAD_HINT="HF_HUB_ENABLE_HF_TRANSFER=1 uv run --with huggingface_hub --with hf_transfer hf download unsloth/Qwen3.6-27B-GGUF --local-dir $SCRIPT_DIR/models/Qwen3.6-27B-GGUF --include '*UD-Q4_K_XL*' --include '*mmproj-F16*'"
    ;;
  35b)
    # MoE 35B total / ~3B active — higher quality but larger RAM footprint
    MODEL="$SCRIPT_DIR/models/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf"
    MMPROJ="$SCRIPT_DIR/models/Qwen3.6-35B-A3B-GGUF/mmproj-F16.gguf"
    ALIAS="unsloth/Qwen3.6-35B-A3B"
    CTX_SIZE=262144  # hybrid MoE KV cache stays small, supports model max
    DOWNLOAD_HINT="HF_HUB_ENABLE_HF_TRANSFER=1 uv run --with huggingface_hub --with hf_transfer hf download unsloth/Qwen3.6-35B-A3B-GGUF --local-dir $SCRIPT_DIR/models/Qwen3.6-35B-A3B-GGUF --include '*UD-Q4_K_XL*' --include '*mmproj-F16*'"
    ;;
  *)
    echo "Usage: $0 [27b|35b] [on|off|budget=N]"
    exit 1
    ;;
esac

# Resolve thinking flags and mode-appropriate sampling.
# Uses --reasoning [on|off] / --reasoning-budget N (server-enforced hard limits).
TOP_K=20
MIN_P=0.00
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
    THINKING_DESC="budget=${BUDGET} tokens (hard cap, precise-coding params)"
    TEMP=0.6; TOP_P=0.95; PRESENCE_PENALTY=0.0
    ;;
  on|*)
    THINKING_FLAGS="--reasoning on --reasoning-budget -1"
    THINKING_DESC="enabled, unlimited (precise-coding params)"
    TEMP=0.6; TOP_P=0.95; PRESENCE_PENALTY=0.0
    ;;
esac

if [ ! -f "$LLAMA_SERVER" ]; then
    echo "Error: llama-server not found. Run ./llama-server-setup.sh first."
    exit 1
fi

if [ ! -f "$MODEL" ]; then
    echo "Error: Model not found at $MODEL"
    echo "Download it with:"
    echo "  $DOWNLOAD_HINT"
    exit 1
fi

# mmproj is optional (enables vision); warn but don't fail if missing.
MMPROJ_FLAG=""
if [ -f "$MMPROJ" ]; then
    MMPROJ_FLAG="--mmproj $MMPROJ"
else
    echo "Note: mmproj not found at $MMPROJ — vision disabled. Re-download with --include '*mmproj-F16*' to enable."
fi

echo "==> Starting llama-server on port 8001..."
echo "    Model: $ALIAS (UD-Q4_K_XL, ctx: $CTX_SIZE)"
echo "    Thinking: $THINKING_DESC"
echo "    Sampling: temp=$TEMP top_p=$TOP_P top_k=$TOP_K min_p=$MIN_P presence_penalty=$PRESENCE_PENALTY"
echo ""
echo "    To use with Claude Code:"
echo "      ANTHROPIC_BASE_URL=http://localhost:8001 ANTHROPIC_API_KEY=sk-no-key-required claude --model $ALIAS"
echo ""

"$LLAMA_SERVER" \
    --model "$MODEL" \
    $MMPROJ_FLAG \
    --alias "$ALIAS" \
    --temp "$TEMP" \
    --top-p "$TOP_P" \
    --top-k "$TOP_K" \
    --min-p "$MIN_P" \
    --presence-penalty "$PRESENCE_PENALTY" \
    --repeat-penalty "$REPEAT_PENALTY" \
    --port 8001 \
    --batch-size 8192 \
    --ubatch-size 512 \
    --parallel 1 \
    --kv-unified \
    --cache-type-k q8_0 --cache-type-v q8_0 \
    --flash-attn on --fit on \
    --ctx-size "$CTX_SIZE" \
    --host 0.0.0.0 \
    $THINKING_FLAGS
