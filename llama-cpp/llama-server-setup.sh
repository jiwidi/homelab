#!/usr/bin/env bash
# Build llama.cpp for Apple Silicon (Metal, no CUDA)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LLAMA_DIR="$SCRIPT_DIR/llama.cpp"

echo "==> Installing dependencies..."
brew install cmake curl

echo "==> Cloning llama.cpp..."
if [ -d "$LLAMA_DIR" ]; then
    echo "    llama.cpp already exists, pulling latest..."
    git -C "$LLAMA_DIR" pull
else
    git clone https://github.com/ggml-org/llama.cpp "$LLAMA_DIR"
fi

echo "==> Building for Apple Silicon (Metal enabled by default)..."
cmake "$LLAMA_DIR" -B "$LLAMA_DIR/build" \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_CUDA=OFF

cmake --build "$LLAMA_DIR/build" --config Release -j --clean-first \
    --target llama-cli llama-mtmd-cli llama-server llama-gguf-split

cp "$LLAMA_DIR/build/bin/llama-cli" "$LLAMA_DIR/"
cp "$LLAMA_DIR/build/bin/llama-server" "$LLAMA_DIR/"

echo ""
echo "Done! llama-server is at: $LLAMA_DIR/llama-server"
echo ""
echo "Next: download Qwen3.6-27B (dense, ~15GB — default, leaves room for KV on 32GB):"
echo "  HF_HUB_ENABLE_HF_TRANSFER=1 uv run --with huggingface_hub --with hf_transfer \\"
echo "      hf download unsloth/Qwen3.6-27B-GGUF \\"
echo "      --local-dir $SCRIPT_DIR/models/Qwen3.6-27B-GGUF \\"
echo "      --include '*UD-Q4_K_XL*' --include '*mmproj-F16*'"
echo ""
echo "Then start the server with: ./llama-server-start.sh"
