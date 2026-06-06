---
name: rust-language
description: Rust language patterns for AI infra and systems code. Covers ownership/borrowing tricks (split_at_mut, take/mem::take), FFI to C/CUDA (unsafe extern "C", #[link], DevicePtr), anyhow error handling, lifetime annotations, async runtimes, Cargo workspaces, and nightly-only features commonly used in inference engines (pegainfer, vLLM-rs, candle, etc.). Use when writing, reviewing, or debugging Rust in a GPU/systems context.
---

# Rust for AI Infra & Systems Code

A focused reference for the Rust patterns that show up in GPU inference engines, kernel runtimes, and high-performance systems code. Assumes intermediate Rust — covers the **edge cases and conventions**, not the basics.

## Workspace & Module Layout

### Flat layout (pegainfer convention)
```
pegainfer-qwen35-4b/
├── src/
│   ├── lib.rs
│   ├── prefill.rs          # module root
│   ├── prefill_buffers.rs  # sibling module
│   ├── prefill/            # submodules (when needed)
│   │   ├── mod.rs
│   │   └── ...
```
- `src/foo.rs` declares `mod foo;` from `lib.rs`
- `src/foo/` is the submodules directory (NOT `src/foo/mod.rs`)
- This is the opposite of the old `mod.rs` style — enforced by repo convention

### Cargo workspaces
- Virtual workspace root has no `package` block — only `[workspace]`
- Each member crate has its own `Cargo.toml`
- Shared deps are listed in `[workspace.dependencies]` and inherited as `dep.workspace = true`
- Feature-gated crates: `pegainfer-deepseek-v4` etc. live behind `--features deepseek-v4` so default builds stay light

## Ownership & Borrowing Tricks

### Avoiding split-borrow
```rust
// BAD: can't mutably borrow graph_state.graphs while also borrowing graph_state.buffers
let result = graph_state.graphs[bucket_idx].run_or_capture(&self.ctx, || {
    self.batch_decode_kernels_graph(..., &mut graph_state.buffers)
});

// GOOD: mem::take to break the borrow
let mut graphs = std::mem::take(&mut graph_state.graphs);
let result = graphs[bucket_idx].run_or_capture(&self.ctx, || {
    self.batch_decode_kernels_graph(..., &mut graph_state.buffers)
});
graph_state.graphs = graphs;
```

### split_at_mut
```rust
let (left, right) = self.slot_states.split_at_mut(last);
let src = &right[0].layers[layer_idx];
let dst = &mut left[idx].layers[layer_idx];
// now both `src` (immutable) and `dst` (mutable) are independent
```

### Iterating with take
```rust
// Drain a Vec while keeping the original binding around
let token_ids_padded = token_ids.to_vec();  // copy
// or
let mut token_ids_padded = token_ids.iter().copied().collect::<Vec<_>>();
```

## FFI to C / CUDA

### extern "C" + #[link]
```rust
#[link(name = "cudart")]
unsafe extern "C" {
    #[link_name = "cudaProfilerStart"]
    fn cuda_profiler_start() -> i32;
    #[link_name = "cudaProfilerStop"]
    fn cuda_profiler_stop() -> i32;
}
```

### Vendor-style FFI modules
pegainfer wraps CUDA kernels in `src/ffi.rs` with a single-line re-export:
```rust
// ffi.rs
include!(concat!(env!("OUT_DIR"), "/bindings.rs"));
```

Then call sites import the typed signatures:
```rust
use crate::ffi;
unsafe {
    ffi::paged_kv_scatter_cuda(/* ... lots of raw pointers ... */);
}
```

### Raw pointer + device pointer dance (cudarc)
```rust
let (buf_ptr, _guard) = kv_state.buffer().device_ptr(&self.ctx.stream);
let (kc_ptr, _gkc) = kc.data.device_ptr(&self.ctx.stream);
let result = unsafe {
    ffi::paged_kv_scatter_cuda(
        buf_ptr as *const ffi::Half,
        kc_ptr as *const ffi::Half,
        // ...
        self.ctx.stream.cu_stream(),
    )
};
```
- `device_ptr()` returns a raw pointer + a guard that prevents the stream from advancing until the guard drops
- Drop the guard LAST (latest in the function) so the kernel sees consistent state
- `as *const ffi::Half` (or `*mut`) is the cast that bridges `cudarc` types and your FFI bindings

### unsafe blocks — keep them small and labeled
```rust
unsafe {
    // SAFETY: pointers come from device_ptr() above, all with lifetime guards
    // held in scope; cu_stream is the same stream the GPU buffers were allocated on.
    ffi::paged_kv_scatter_cuda(/* ... */);
}
```

## Error Handling — anyhow

pegainfer uses `anyhow::Result<T>` everywhere, with three patterns:

### 1. anyhow! for ad-hoc errors
```rust
return Err(anyhow!("Qwen3.5 engine supports exactly one CUDA device, got {}", ordinals.len()));
```

### 2. bail! for early-return guards
```rust
anyhow::ensure!(bs > 0, "batch_decode_graph requires at least one request");
anyhow::ensure!(bs == kv_states.len(), "token_ids / kv_states len mismatch");
```

### 3. .context() / .with_context() for wrapping
```rust
let logits_f32 = logits.to_host(self.model.device_ctx())
    .with_context(|| format!("Qwen3.5 logits to_host failed for request {}", req.request_id.get()))?;
```

`anyhow::Error::msg` is fine for the simplest cases. Avoid defining a custom `Error` enum in model crates — the cost outweighs the benefit.

## Async / Runtime

pegainfer's scheduler uses `std::thread` + crossbeam channels, not tokio. The hot path is GPU-bound; CPU work is minimal:
```rust
let (tx, rx) = std::sync::mpsc::sync_channel::<TokenEvent>(64);
std::thread::spawn(move || {
    scheduler.run(rx, model)
});
```

If you DO need async:
- `tokio` for HTTP frontends (pegainfer-vllm-frontend uses axum)
- `async-channel` for simpler in-process channels (no tokio dep)
- For GPU streams, `cudarc` is fully synchronous from the host's perspective — you just enqueue and the stream executes

## Lifetimes

### 'static for compile-time configs
```rust
pub static KERNEL_PLAN: KernelPlan = KernelPlan {
    model: "qwen3-4b",
    phases: &[KernelPhase { name: "prefill", ops: &[/* ... */] }],
};

pub fn kernel_plan() -> &'static KernelPlan { &KERNEL_PLAN }
```
All `&'static str` and `&'static [...]` — no allocation, no runtime cost.

### Lifetime elision in FFI wrapper structs
```rust
pub struct PrefillPlan<'a> {
    pub requests: &'a [PrefillStepItem],
}
```
Read as: "borrows from a slice that lives at least as long as `'a`." Required when wrapping caller-owned slices for the scheduler.

## Static Assertions & Invariants

```rust
// Debug-only invariant — runs in tests, stripped in release
debug_assert_eq!(bufs.logits.seq_len, padded_bs);

// Compile-time check
const _: usize = assert!(std::mem::size_of::<Half>() == 2);
```

## Common Crate Conventions in pegainfer

| Crate | Purpose | Notes |
|-------|---------|-------|
| `anyhow` | Error handling | `Result<T>` everywhere in model crates |
| `cudarc` | CUDA driver binding | `DevicePtr` / `DevicePtrMut` with guards |
| `half` | bf16/f16 types | `bf16::from_f32`, `.to_f32()` |
| `serde` + `serde_json` | Config + manifests | `qwen3-4b.toml` kernel manifest |
| `clap` | CLI parsing | `#[derive(Parser)]` in bins |
| `rand` | RNG | `StdRng::seed_from_u64(seed)` for determinism |
| `criterion` (in benches) | Bench harness | `benches/ops/` has a `common/mod.rs` with helpers |
| `pegainfer-core` | Shared abstractions | `engine::EngineHandle`, `kv_pool::KvState`, `tensor::DeviceContext` |

## Common Pitfalls

### 1. Stream guards drop early
The `_gqc`, `_gkc`, etc. guards must outlive the FFI call. Put them in the same scope as the kernel launch, NOT extracted via `let (ptr, _g) = ...` then `ptr` used in a different scope.

### 2. Bucket-padded decode batches
When you pad a decode batch to a CUDA Graph bucket size, **every** operation that uses slot indices (e.g., recurrent state) must also iterate over the padded size, not the real batch size. Skipping padding slots breaks pointer stability for the next capture.

### 3. async/await on GPU streams
cudarc is sync. If you write `async fn` that calls a kernel, you're blocking the executor thread the whole time. Use spawn_blocking or, better, dedicated threads.

### 4. Cargo features don't compose
`--features deepseek-v4` enables deepseek. `--features deepseek-v4,kimi-k2` enables both. But feature-gated code paths often have hidden inter-deps in `pegainfer-kernels/build.rs` — check the build script before assuming two features work together.

## Testing Patterns

### Unit tests inline
```rust
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn checked_prefill_end_pos_rejects_overflow() {
        let err = checked_prefill_end_pos(usize::MAX, 1, 262_144)
            .unwrap_err()
            .to_string();
        assert!(err.contains("prefill position overflow"));
    }
}
```

### Integration tests under `tests/`
- `tests/common/mod.rs` — shared helpers (model path, sample gen)
- `tests/hf_golden_gate.rs` — accuracy gate against stored safetensors
- `tests/e2e_scheduler.rs` — scheduler liveness, request flow

### Skip patterns
```rust
fn get_model_path_or_skip() -> Option<String> {
    match std::env::var("PEGAINFER_TEST_MODEL_PATH") {
        Ok(path) => Some(path),
        Err(_) if Path::new(MODEL_PATH).join("config.json").exists() => Some(MODEL_PATH.to_string()),
        Err(_) => {
            eprintln!("skipping ... because model is missing");
            None
        }
    }
}
```

## Performance / Profiling Hooks

- `PEGAINFER_BUILD_TIMING=1` — prints per-phase build timings
- `pegainfer-cupti::profile_range_with_prepare` — wrap a kernel launch for CUPTI
- `cudaProfilerStart/Stop` — exposed via `#[link(name = "cudart")]` in `qwen3_decode_context.rs` bin
- For nsys integration, see the `.claude/skills/nsys-profiling` skill in pegainfer

## Pre-PR Checklist (always run before pushing)

**Step 1 — quick standalone syntax check (no toolchain deps needed, ~5s):**

```bash
# For a new file that uses only stdlib:
rustc --edition 2024 --crate-type lib --emit=metadata -o /tmp/check path/to/new_file.rs

# Or for a file in a specific edition (check Cargo.toml first):
rustc --edition 2021 --crate-type lib --emit=metadata -o /tmp/check path/to/new_file.rs
echo "EXIT=$?"  # must be 0
```

This catches:
- Syntax errors
- Borrow / lifetime errors that don't need the crate's full type context
- Edition 2024 features used incorrectly (e.g., `if let` chains, `gen` blocks, etc.)

This does NOT catch:
- Missing imports from sibling modules
- Trait bounds you missed
- Linker errors (you need a real `cargo check` for those)

**Step 2 — `cargo check` for the whole crate (or as much as the build allows):**

```bash
cargo check -p <crate-name> --lib
```

If the build script has hard CUDA / native deps you can't install, try the `cargo check` anyway to see how far it gets. Then make a clear note in the PR description: "standalone rustc check passed; full cargo check blocked by `<reason>`; maintainer's CI will catch the rest."

**Why this matters:** a 5-second standalone `rustc` check is the cheapest signal that the new file is even valid Rust. Skipping it and pushing untested code is how typos like `fn pub kernel_plan()` (syntax error) or `pub const KERNEL_PLAN: &KernelPlan = ...` (lifetime error on a static) make it into PRs.
