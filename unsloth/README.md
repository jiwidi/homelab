# Unsloth — local LLM server

Self-hosted OpenAI-compatible LLM endpoint for continuous agent workloads,
running on Unsloth's prebuilt llama.cpp (Metal).

```bash
./qwen-server.sh          # thinking on (default)
./qwen-server.sh off      # non-thinking, faster
./qwen-server.sh budget=512
```

Endpoint: `http://<host>:8001/v1` — auth via `Authorization: Bearer $LLM_API_KEY` (see `.env`).

---

## Hardware reality: this machine is bandwidth-bound

Mac mini `Mac16,10` — **M4 base** (4P+6E), 32 GB unified memory, **~120 GB/s**
memory bandwidth. Note this is the *base* M4, not the M4 Pro (273 GB/s) that
most online benchmarks quote — expect roughly half their numbers.

Generation speed is set by how many bytes must be read per token, so it scales
with **active** parameters, not total parameters. Measured here:

| Model | Active params | Bytes/token | Measured |
|---|---|---|---|
| Qwen3.8-27B dense, Q4_K_M | 27B (all) | 17.1 GB | **5.0 tok/s** |
| Qwen3.6-35B-A3B MoE, UD-Q4_K_XL | ~3B | ~2 GB | see below |

5.0 tok/s × 17.1 GB ≈ 85 GB/s effective — about 71% of theoretical peak, i.e.
the dense model was already running near hardware limits. It cannot be tuned
faster. A 27B dense model is simply the wrong shape for this box: fine for
one-off questions, unusable for agents that emit thousands of tokens per turn.

**Rule of thumb: on this machine, prefer MoE models with a small active-param
count.** Total size costs RAM; active size costs speed.

## Why context is cheap here

`Qwen3.6-35B-A3B` is a hybrid-attention MoE. Only **10 of 40 layers** use full
attention (`full_attention_interval=4`), and those have just 2 KV heads. The
other 30 layers use linear attention with constant-size recurrent state that
does not grow with context.

KV cost is ~10.6 KiB/token at `q8_0`:

| Context | KV cache |
|---|---|
| 128k | 1.4 GB |
| **256k (native max)** | **2.9 GB** |

A conventional dense model would need roughly 4–8× this. **Context is not the
binding constraint on this hardware — weight size is.** Don't trade quantization
quality for context length; you have context to spare.

## Memory budget (~26 GB of 32 GB)

```
weights (UD-Q4_K_XL)      22.4 GB
KV cache @ 256k, q8_0      2.9 GB
Metal compute buffers     ~1.5 GB
                          -------
                          ~26.8 GB
```

This only fits because **Docker Desktop is capped at 12 GB**. It was previously
allocated all 32 GB, which drove ~22 GB of swap and would make the LLM thrash.
The cap lives in `~/Library/Group Containers/group.com.docker/settings-store.json`
(`MemoryMiB: 12288`); containers idle at ~1.5 GB.

If you need more headroom, lower the context rather than the quant:
`CTX_OVERRIDE=131072 ./qwen-server.sh` saves 1.5 GB.

## Read this first: oMLX is faster

See `../omlx/` — oMLX benchmarked **34.7 tok/s vs 26.0** for llama.cpp+MTP on
this model, and 3.4s vs 6.1s on cached agent turns. oMLX is the recommended
default. This folder remains useful for fine-grained quant control (IQ4_XS,
Q5_K_S, …), grammar-constrained generation, and vision.

To run the MTP build here (faster than the plain GGUF):

```bash
~/.unsloth/llama.cpp/build/bin/llama-server \
  --model models/Qwen3.6-35B-A3B-MTP-GGUF/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf \
  --spec-type draft-mtp --spec-draft-n-max 2 ...
```

MTP disables `--mmproj` and `-np > 1`, so use the non-MTP GGUF for vision.

## Use Unsloth's llama.cpp build

The old `llama-cpp/` folder (since deleted) was pinned to commit `a702f39`
(2026-04-24) and predated the `qwen35` architecture these models use — it could
not load them. Unsloth ships a prebuilt Metal llama.cpp at
`~/.unsloth/llama.cpp/` (b10360) supporting `qwen35` / `qwen35moe`. The launcher
points there deliberately; don't rebuild against an older checkout.

## Network access

The server binds `0.0.0.0:8001`, reachable two ways:

- **LAN** — `http://192.168.31.58:8001/v1` from any device on the WiFi.
- **Twingate VPN** — the connector runs in `network_mode: host`, so it can
  already reach the host. Add a Resource in the Twingate admin console pointing
  at `192.168.31.58:8001` and grant it to your group.

Because it listens beyond localhost, the launcher **requires** an API key and
refuses to start without one. It's in `.env` (gitignored). To bind locally only:
`HOST_BIND=127.0.0.1 ./qwen-server.sh`.

> Note: llama-server sets CORS to allow all origins. Keep this off the public
> internet — LAN and VPN only. Don't port-forward 8001.

## Sampling params

Per model family — **these are not interchangeable**:

| | temp | top_p | top_k | min_p | presence |
|---|---|---|---|---|---|
| Qwen3.6 thinking | 0.6 | 0.95 | 20 | 0.0 | 0.0 |
| Qwen3.6 non-thinking | 0.7 | 0.80 | 20 | 0.0 | 1.5 |
| Qwen3.8 thinking | **1.0** | 0.95 | 20 | 0.0 | 0.0 |

The launcher sets these automatically based on the thinking mode argument.

## Using with Claude Code

```bash
ANTHROPIC_BASE_URL=http://192.168.31.58:8001 \
ANTHROPIC_API_KEY=$LLM_API_KEY \
claude --model unsloth/Qwen3.6-35B-A3B
```

## Revisiting Qwen3.8

Qwen3.8-27B (dense) was downloaded, benchmarked at 5 tok/s, and removed — the
architecture is sound (it's also hybrid-attention, 16/64 full-attn layers, 256k
native) but dense weights are fatal on 120 GB/s. The only Qwen3.8 MoE released
so far is `Qwen3.8-2.4T-A95B`, far too large. **Revisit when an A3B-class
Qwen3.8 MoE ships.**

Note: llama.cpp ignores the models' MTP / `nextn` layer (block 64), so
speculative multi-token prediction is unavailable — it logs
`unused tensor blk.64.nextn.*` on load, which is expected, not an error.
