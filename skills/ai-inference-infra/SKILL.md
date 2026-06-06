---
name: ai-inference-infra
description: LLM inference engine architecture and kernel-level decisions. Covers paged attention (vLLM-style), KV cache layouts (HND vs paged), prefill/decode split, CUDA Graph capture/replay, linear attention (GDR / Mamba / RWKV), token sampling (greedy, top-k, top-p, FlashInfer), multi-GPU (TP/EP/PP), kernel selection manifests, and performance debugging (nsys, NCU, CUPTI). Use when working on, debugging, or designing an LLM inference engine — pegainfer, vLLM, TensorRT-LLM, SGLang, llama.cpp, candle, etc.
---

# LLM Inference Infrastructure

Architecture and kernel-level decisions for LLM inference engines. Focused on what makes a decode loop fast, what makes prefill scale, and why every engine eventually re-invents the same pieces.

## Mental Model: the inference loop

```
HTTP request → tokenize → prefill(prompt) → decode(token-by-token) → detokenize → stream
                                       ↑                                    ↓
                                       └──── KV cache (paged, ~5MB/req) ───┘
```

**Two fundamentally different shapes**:
- **Prefill**: process all prompt tokens in parallel. Compute-bound (matmels dominate). Latency sensitive (TTFT).
- **Decode**: generate one token at a time per request. Memory-bandwidth bound (loading weights). Throughput sensitive (TPOT, batch size).

Engines split these into separate kernels and schedule them differently. Confusing the two is the #1 source of perf bugs.

## Paged Attention (vLLM's key idea)

### Why pages?
- Naive KV cache: pre-allocate `max_seq_len × num_layers × 2 × num_heads × head_dim × sizeof(dtype)` per request
- Paged: allocate `page_size × num_layers × 2 × num_heads × head_dim × sizeof(dtype)` blocks on demand

This drops wasted memory from ~50% to <5% under realistic workloads.

### Metadata (per request)
```
page_indices:    i32[]   flat list of page IDs this request owns
page_indptr:     i32[]   CSR-style: indptr[req_i] = start of req_i's slice in page_indices
last_page_len:   i32[]   how many tokens are valid in the last page (page_size except possibly the last)
```

This CSR (compressed sparse row) layout lets the attention kernel do `for page_id in page_indices[indptr[req_i]..indptr[req_i+1]]` — exactly one gather per page.

### pegainfer qwen3 example
```rust
ops::paged_attention_batch_decode_hd256_into(
    &self.ctx,
    &bufs.q_attn, &bufs.k_attn, &bufs.v_attn,
    kv_buffer, layout, layer_idx,
    &bufs.page_indices_d,    // CSR
    &bufs.page_indptr_d,     // CSR
    &bufs.last_page_len_d,   // CSR
    &bufs.positions_d,       // current decode position per request
    &bufs.request_indices_d, // request id per slot
    &bufs.kv_tile_indices_d, // pre-computed tile schedule
    &bufs.kv_chunk_size_d,
    &mut bufs.attn_out_full,
    num_attention_heads, batch_size,
)?;
```

### HND vs paged (prefill staging)
Many engines use a contiguous HND staging buffer for prefill (handwritten matmels, conv1d, etc.) then **scatter** to the paged pool:
```
[prefill HND write buffer]  --paged_kv_scatter_cuda-->  [paged KV pool]
```
The scatter is one kernel, the attention over paged pool is the next. pegainfer does this in `prefill::prefill_full_attention` for Qwen3.5.

## Kernel Selection

Every modern engine has a `kernel_plan` or equivalent — a static description of "which kernel serves which op, on which backend." Reasons:
- Debugging: "I see weird numerics, what kernels ran?"
- AOT codegen: Triton/TileLang generate variants per shape, need a manifest
- Static review: PR reviewers can see the full kernel surface

pegainfer's qwen3-4b defines:
```rust
pub struct KernelOp {
    pub id: &'static str,        // "paged_decode_attention"
    pub rust: &'static str,      // "batch_decode::batch_decode_layer -> ops::batch_decode_with_paged_kv"
    pub backend: &'static str,   // "FlashInfer"
    pub notes: &'static str,     // "paged KV read with per-request CSR metadata"
}
```

The pattern: id is the logical op, rust is the call site, backend is the runtime, notes are why this kernel (not another). For an issue like pegainfer #256, the deliverable is to add a parallel `kernel_plan.rs` to a crate that doesn't have one yet.

### Kernel manifest (TOML)
For AOT codegen, you also need a manifest that says "for batch_size [1, 2, 4, 8], kv_len [128, 512, ..., 10000], generate variants [non_partition, split_kv_256x64, split_kv_512x64]":
```toml
[[ops]]
name = "paged_decode_attention"
phase = "decode"
batch_size = [1, 2, 4, 8, 16, 32]
kv_len = [128, 512, 1024, 2048, 4096, 8192, 10000]
variants = ["non_partition", "split_kv_256x64", "split_kv_512x64"]
```
The kernel_report bin then measures each variant and produces a per-op report.

## Backends

| Backend | Used for | When to choose |
|---------|----------|----------------|
| **CUDA (raw .cu)** | Custom kernels (gated delta rule, conv1d, attention gate) | Shape is too weird for a library; you need exact control |
| **cuBLAS** | GEMM, GEMV | Default for projections (Q/K/V/O, gate/up/down, LM head) |
| **FlashInfer** | Attention (prefill + decode), sampling, top-k | Standard for any attention path on Hopper/Ada |
| **Triton AOT** | Generated kernels at build time | Variant space is large (head dims, batch sizes); the codegen is worth it |
| **TileLang** | DeepSeek-style indexer + MoE | When Triton is too imperative; lets you express tiles as data |
| **CuTe DSL** | MLA decode (Kimi-K2) | When FlashInfer doesn't support your attention pattern |
| **Marlin** | INT4 GEMM (Kimi-K2) | Quantized weights; ~2-4× faster than bf16 GEMV on small batches |

## CUDA Graph

### Why
Each `cudaLaunchKernel` is ~5μs of host overhead. A decode step that issues 50 kernels = 250μs of pure CPU. For bs=1 decode (memory bound, kernel time ~5ms), this is 5% overhead. For larger batches with more ops, it can dominate.

**CUDA Graph** captures the entire kernel sequence + memory operations into a single replayable graph. Replay cost is ~5μs total, regardless of kernel count.

### Pointer stability constraint
CUDA Graph capture records absolute device pointers. If you reuse scratch buffers across iterations, the pointer can change when the buffer is reallocated. Solutions:
- Pre-allocate ALL buffers at max batch size, never grow them
- Use bucket-padded batches (e.g., `[1, 2, 4, 8, 16, 32]`) so the same graph captures all sizes in a bucket
- "Padding slots" point to a reserved dummy page; their output is ignored

### Capture vs replay
```rust
// First call: capture
graphs[bucket_idx].run_or_capture(&self.ctx, || {
    // closure runs once during capture
    self.batch_decode_kernels_graph(...)
})?;

// Subsequent calls: replay
graphs[bucket_idx].replay()?;
```

### pegainfer's decode pattern
- `BATCH_BUCKETS = [1, 2, 4, 8, 16, 32]` — decode batches snap to nearest bucket
- `graph_state.buffers` pre-allocated at max bucket size
- `graph_state.slot_states` is a fixed `[RecurrentState; MAX_BATCH]` (one per slot)
- Padding slots (real_bs..padded_bs) run but their results are discarded

## Linear Attention (GDR / Mamba / RWKV)

For hybrid models (Qwen3.5, Jamba, Zamba, Granite-Hybrid), some layers are linear-attention with recurrent state per request, others are full attention with paged KV.

### Gated Delta Rule (Qwen3.5 linear layers)
- 24 of Qwen3.5's 36 layers are linear
- Each linear layer has a recurrent state of size `num_value_heads × val_dim × key_dim` per request
- For decode: state update is O(state_size) per request — extremely fast
- For prefill: chunkwise (split seq into chunks of e.g. 64 tokens, do a chunk-local triangular solve, then accumulate state)

### State lifecycle
- Allocated in `RecurrentState` per request
- Lives across decode steps (it's the entire reason linear attention is fast)
- For CUDA Graph: must be a fixed `[RecurrentState; MAX_BATCH]` array — slot index = position in the array

### conv1d
- Linear attention layers have a depthwise conv1d BEFORE the GDR step
- Conv state is `num_channels × (kernel_size - 1)` per request
- Updated in-place each step

## Sampling

### Greedy
Argmax over logits. Trivial on CPU, one kernel on GPU.

### Top-k / top-p / temperature
FlashInfer's `flashinfer_topk` (a.k.a. RadixTopK) is the standard:
- Build a top-k subset of the vocab (e.g., top 1024 of 128k)
- Apply temperature, then top-p (nucleus) filter
- Sample from the resulting distribution

### State shape
pegainfer's sampling signature:
```rust
ops::gpu_sample_into(
    &ctx, &logits,                  // input: vocab logits
    &mut probs,                     // scratch
    &mut top1_value,                // scratch
    &mut sample_row_states,         // scratch (per-row state)
    &mut sample_valid,              // scratch
    &mut sample_out,                // output: one i32 token id
    &params,                        // SamplingParams { temperature, top_k, top_p, ... }
    random_val,                     // f32 in [0, 1) for sampling
)?;
```

## Multi-GPU

### Tensor Parallel (TP)
- Each GPU holds a slice of every weight
- All-reduce after each layer's matmul
- Best for: tensor-bound layers (large GEMM)
- Communication: NCCL all-reduce, ~few μs on NVLink, ~tens of μs on IB

### Expert Parallel (EP)
- Each GPU holds a subset of experts (MoE models)
- All-to-all to route tokens to the GPUs that own their assigned experts
- Best for: MoE with many experts (DeepSeek, Mixtral, Kimi-K2)
- Communication: NCCL all-to-all, more expensive than all-reduce; latency-sensitive

### Pipeline Parallel (PP)
- Layers split across GPUs; one GPU computes layers 0-N, next computes N-M, etc.
- Bubbles between stages hurt throughput
- Rarely used in modern engines; usually TP+EP is enough

### pegainfer's mix
- Qwen3-4B: TP-only (always built, scales to N GPUs)
- Qwen3.5-4B: single-GPU only (24+8 layers fit on one GPU)
- DeepSeek-V4: TP+EP, 8-GPU
- DeepSeek-V2-Lite: EP, 2-GPU
- Kimi-K2: MLA + MoE + Marlin INT4, 8-GPU EP

## Continuous Batching

Engines don't wait for one batch to finish before accepting new requests. vLLM's iteration-level scheduling:
- Each "step" picks the next chunk of work (prefill, decode, swap) from a global queue
- New requests can join at any step
- Finished requests' KV cache is freed as soon as they complete

pegainfer's `unified_step` does this:
```rust
fn unified_step(
    &self,
    prefill_prompts: &[&[u32]],          // new requests
    prefill_kv_states: &mut [KvState],
    prefill_recurrent_states: &mut [&mut RecurrentState],
    decode_tokens: &[u32],                // existing requests
    decode_kv_states: &mut [&mut KvState],
    graph_state: &mut BatchDecodeGraphState,
) -> Result<(Vec<DeviceVec>, Vec<DeviceVec>)>;
```

## Performance Debugging

### nsys
- **MUST** use `--cuda-graph-trace=node` — without it, CUDA Graph replay is opaque (one block, no individual kernels)
- **WARNING**: `--cuda-graph-trace=node` inflates absolute times by 30-60%. Use for proportions only; measure real TPOT with `bench_serving` *without* nsys
- See the `nsys-profiling` skill in pegainfer for the full workflow

### NCU
- Kernel-level roofline analysis
- Compute achieved vs peak FLOPS
- Memory bandwidth achieved vs peak
- Use after nsys identifies the slow kernel — NCU gives you WHY

### CUPTI
- Custom metrics (occupancy, warp issue stalls, etc.)
- pegainfer exposes `pegainfer_cupti::profile_range_with_prepare` for embedding CUPTI in custom code

### Common red flags
- `cuStreamSynchronize` during inference (not loading) → unnecessary D2H copy or sync point
- High `cudaLaunchKernel` count × 5μs → kernel fusion or CUDA Graph opportunity
- `cuMemAllocAsync` during inference → per-step allocation that should be pre-allocated
- Tail latency p99 >> p50 in MoE → expert routing imbalance (route tokens to underused experts)

## Build System

The pegainfer-kernels `build.rs` orchestrates everything:
1. Compile `csrc/*.cu` with nvcc (auto-detect SM targets, or `PEGAINFER_CUDA_SM=120,80` override)
2. Run Triton AOT via `tools/triton/gen_triton_aot.py` (for Qwen3.5 kernels)
3. Feature-gated:
   - `deepseek-v4` → TileLang + CuTe codegen
   - `kimi-k2` → additional MLA/MoE/Marlin CUDA

Build flags you actually use:
- `--release` — ALWAYS. Debug builds are 10×+ slower for GPU.
- `--features kimi-k2` — opt in to gated models
- `PEGAINFER_CUDA_SM=120,80` — override SM detection (e.g., when nvidia-smi is blocked)
- `PEGAINFER_BUILD_TIMING=1` — print per-phase timings
- `PEGAINFER_NVCC_JOBS=N` — limit parallel nvcc jobs (default uses all cores; sometimes too much memory)

## Common Architectural Smells

1. **"Hardwired kernel choice"** — kernel picked at every call site based on shape if-else. Fix: centralize in a `kernel_plan` or factory.
2. **"Magic numbers in kernels"** — `if seq_len > 10000 { /* use long-context kernel */ }`. Fix: explicit plan with named variants.
3. **"Pointer changes between iterations"** — scratch buffer reallocates. Breaks CUDA Graph. Fix: pre-allocate to max size.
4. **"Per-step alloc"** — `Vec::new()` in a hot loop. Fix: pre-allocate outside the loop.
5. **"Synchronous H2D inside decode"** — `cudaMemcpy` blocks the host. Fix: batch all H2D, then issue kernels.
6. **"No model report"** — can't tell which kernels ran. Fix: emit a `kernel_report` or `model_report` on startup.

## Writing a `kernel_plan` Descriptor (post-mortem lessons from pegainfer #256)

When you're adding a static descriptor (kernel_plan, kernel_ledger, op_manifest, etc.) that documents "which kernel serves which op," the temptation is to add 'value-add' fields beyond what's strictly required. Don't.

### The 4 hard rules

1. **Symbol names lie.** A function called `silu_mul_triton_aot_cuda` may be a hand-written CUDA kernel, not Triton AOT. A file called `flashinfer_norm.cu` may or may not actually use `flashinfer::norm::*` — only `grep '#include <flashinfer/' file.cu` proves it. **Never label a backend without reading the .cu file**.

2. **The `#include <flashinfer/*>` rule.** Any .cu file that includes a `<flashinfer/*.cuh>` header AND calls a `flashinfer::*::*` template function is genuinely backed by FlashInfer. If the file is named `flashinfer_*.cu` but the include is missing, it's a misleading legacy name — the kernel is plain CUDA.

3. **csrc paths are derivable, don't store them.** The Rust function name (in the `rust` field) is enough to grep the codebase. Storing csrc paths in the descriptor produces drift the moment someone reorganizes csrc/ (which happens — e.g., pegainfer PR #206 split csrc/ by owning model). The kernel ledger (separate, structured) is the right place for paths.

4. **One Rust function = one op.** Even when the Rust function internally launches 2-3 CUDA kernels (like a wrapper that does scatter + attention), keep it as one op. Resist the urge to enumerate components in the ID (e.g., `in_proj_qkvzab` listing 6 letters is wrong if there are only 4 weight matrices and one of them fuses 3 outputs). Use a semantic ID and explain the internal structure in `notes`.

### The verification protocol (1 hour, do it ONCE up-front)

For every op in the descriptor, trace through 3 layers:

```
Rust call site            (your_crate/src/*.rs)
        ?
      ops layer            (your_crate/src/ops.rs OR pegainfer-core/src/ops/*.rs)
        ?
      FFI declaration      (pegainfer-kernels/src/ffi/*.rs)
        ?
      csrc implementation  (pegainfer-kernels/csrc/**/*.cu)
```

For each layer, grep:

```bash
# Find ops layer
grep -rln "pub fn YOUR_OPS_FN\b" pegainfer-kernels/src/ pegainfer-core/src/ | head -1

# Find FFI declaration
grep -nE "pub fn YOUR_FFI_FN\b" pegainfer-kernels/src/ffi/*.rs

# Find csrc implementation
grep -rln "^[A-Za-z_ ]*YOUR_FFI_FN\b" pegainfer-kernels/csrc/

# Check if it really uses FlashInfer
grep -nE '#include <flashinfer/|flashinfer::' pegainfer-kernels/csrc/PATH/TO/file.cu
```

Build a one-page truth table BEFORE writing the descriptor. Skipping this turns a 1-hour task into 3 PRs and multiple AI reviewer cycles.

### What AI code reviewers (codex, gemini-code-assist, etc.) catch and miss

**Catch**: local syntax errors, formatting inconsistencies, obvious cross-row inconsistencies in a single diff.

**Miss**: ground-truth backend mislabels (they don't actually grep your .cu files); deep semantic accuracy (the 'is the file `flashinfer_norm.cu` actually using FlashInfer' question); cross-file invariants. The only fix for these is a complete grep-pass by a human or a much-more-aggressive AI pass.

Do not rely on AI reviewers as your verification step. Use them as the *last* step, after you've grep'd the whole table yourself.
