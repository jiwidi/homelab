#!/usr/bin/env bash
# Start llama-server for Claude Code integration (Apple Silicon / Metal)
# Usage: ./llama-server-start.sh [4b|35b|coder-next] [on|off|budget=N]
#   Thinking (ignored for coder-next — it's a non-thinking model):
#   on          — thinking enabled, no token limit   (temp=0.6, top_p=0.95)
#   off         — thinking disabled (default; best for agentic/coding)  (temp=0.7, top_p=0.8)
#   budget=512  — thinking HARD-capped at N tokens via --reasoning-budget (temp=0.6, top_p=0.95)
#
# Param rationale (Unsloth guide):
#   thinking+coding:      temp=0.6, top_p=0.95, top_k=20, min_p=0.0
#   non-thinking general: temp=0.7, top_p=0.8,  top_k=20, min_p=0.0
#
# NOTE: chat-template-kwargs thinking_budget is only a hint; use --reasoning-budget for hard limit.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LLAMA_SERVER="$SCRIPT_DIR/llama.cpp/llama-server"
MODEL_ARG="${1:-35b}"
THINKING_ARG="${2:-off}"   # default off: no overthinking on "hi", faster agentic responses

case "$MODEL_ARG" in
  4b)
    MODEL="$SCRIPT_DIR/models/Qwen3.5-4B-GGUF/Qwen3.5-4B-UD-Q4_K_XL.gguf"
    ALIAS="unsloth/Qwen3.5-4B"
    CTX_SIZE=65536   # needs 41k+ for Claude Code system prompt
    TOP_K=20; MIN_P=0.00   # TEMP/TOP_P resolved per thinking mode below
    THINKING_MODEL=true
    THINKING_NEEDS_EXPLICIT_ENABLE=true   # small models: thinking off by default
    DOWNLOAD_HINT="HF_HUB_ENABLE_HF_TRANSFER=1 uv run --with huggingface_hub --with hf_transfer hf download unsloth/Qwen3.5-4B-GGUF --local-dir $SCRIPT_DIR/models/Qwen3.5-4B-GGUF --include '*UD-Q4_K_XL*'"
    ;;
  35b)
    MODEL="$SCRIPT_DIR/models/Qwen3.5-35B-A3B-GGUF/Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf"
    ALIAS="unsloth/Qwen3.5-35B-A3B"
    CTX_SIZE=262144  # model max; KV ~2.7GB (hybrid MoE, only 10 attn layers); leaves ~6GB free; --fit handles OOM
    TOP_K=20; MIN_P=0.00   # TEMP/TOP_P resolved per thinking mode below
    THINKING_MODEL=true
    THINKING_NEEDS_EXPLICIT_ENABLE=false  # 35b: thinking on by default
    DOWNLOAD_HINT="HF_HUB_ENABLE_HF_TRANSFER=1 uv run --with huggingface_hub --with hf_transfer hf download unsloth/Qwen3.5-35B-A3B-GGUF --local-dir $SCRIPT_DIR/models/Qwen3.5-35B-A3B-GGUF --include '*UD-Q4_K_XL*'"
    ;;
  coder-next)
    # 80B MoE, 3B active — non-thinking, fast agentic coding model
    # UD-IQ2_M = 25GB, fits in 32GB with 30GB wired limit
    MODEL="$SCRIPT_DIR/models/Qwen3-Coder-Next-GGUF/Qwen3-Coder-Next-UD-IQ2_M.gguf"
    ALIAS="unsloth/Qwen3-Coder-Next"
    CTX_SIZE=131072  # Claude Code system prompt needs 44k+, model supports 262k, fits at 131k
    TEMP=0.8; TOP_P=0.95; TOP_K=40; MIN_P=0.01  # tested: 0.7 loops, 1.0 ok, 0.8 best quality
    THINKING_MODEL=false
    THINKING_NEEDS_EXPLICIT_ENABLE=false
    DOWNLOAD_HINT="HF_HUB_ENABLE_HF_TRANSFER=1 uv run --with huggingface_hub --with hf_transfer hf download unsloth/Qwen3-Coder-Next-GGUF --local-dir $SCRIPT_DIR/models/Qwen3-Coder-Next-GGUF --include '*UD-IQ2_M*'"
    ;;
  *)
    echo "Usage: $0 [4b|35b|coder-next] [on|off|budget=N]"
    exit 1
    ;;
esac

# Resolve thinking flags and set mode-appropriate sampling params.
# Non-thinking: temp=0.7, top_p=0.8  (Unsloth non-thinking/general)
# Thinking:     temp=0.6, top_p=0.95 (Unsloth thinking/coding)
#
# Uses --reasoning [on|off] and --reasoning-budget N (server-enforced hard limits),
# NOT chat-template-kwargs thinking_budget which is only a model-side hint.
if [ "$THINKING_MODEL" = "false" ]; then
    THINKING_FLAGS="--reasoning off"
    THINKING_DESC="disabled (non-thinking model)"
    # TEMP/TOP_P already set for coder-next above
else
  case "$THINKING_ARG" in
    off)
      THINKING_FLAGS="--reasoning off"
      THINKING_DESC="disabled"
      TEMP=0.7; TOP_P=0.8
      ;;
    budget=*)
      BUDGET="${THINKING_ARG#budget=}"
      THINKING_FLAGS="--reasoning on --reasoning-budget $BUDGET"
      THINKING_DESC="budget=${BUDGET} tokens (hard cap)"
      TEMP=0.6; TOP_P=0.95
      ;;
    on|*)
      THINKING_FLAGS="--reasoning on --reasoning-budget -1"
      THINKING_DESC="enabled (unlimited)"
      TEMP=0.6; TOP_P=0.95
      ;;
  esac
fi

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

echo "==> Starting llama-server on port 8001..."
echo "    Model: $ALIAS (UD-Q4_K_XL, ctx: $CTX_SIZE)"
echo "    Thinking: $THINKING_DESC"
echo ""
echo "    To use with Claude Code:"
echo "      ANTHROPIC_BASE_URL=http://localhost:8001 ANTHROPIC_API_KEY=sk-no-key-required claude --model $ALIAS"
echo ""

"$LLAMA_SERVER" \
    --model "$MODEL" \
    --alias "$ALIAS" \
    --temp "$TEMP" \
    --top-p "$TOP_P" \
    --top-k "$TOP_K" \
    --min-p "$MIN_P" \
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
