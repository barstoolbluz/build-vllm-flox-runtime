# vllm-flox-runtime

Runtime scripts for vLLM model serving, packaged as a Flox catalog package (`flox/vllm-flox-runtime`).

Provides three scripts that handle the full lifecycle of a vLLM inference server: pre-flight validation, model provisioning, and validated serving. Designed to be installed alongside a vLLM Python/CUDA package (e.g., `flox/vllm-python312-cuda12_9-sm120`) in a consuming environment.

## What's in the package

| Output | Contents |
|--------|----------|
| `$out/bin/vllm-preflight` | Port reclaim, GPU health check, optional downstream exec |
| `$out/bin/vllm-resolve-model` | Multi-source model provisioning with atomic swaps and locking |
| `$out/bin/vllm-serve` | Model env loading and validated `vllm serve` execution |

Scripts total ~1,700 lines of hardened Bash with input validation, safe env-file handling, and structured exit codes.

## Scripts

### `vllm-preflight`

Pre-flight validation: reclaims the vLLM port if occupied, checks GPU health, and optionally executes a downstream command.

**Platform**: Linux only (requires `/proc`).

**Usage**:

```bash
vllm-preflight                        # checks only
vllm-preflight ./start.sh ...         # checks, then runs command
vllm-preflight -- python -m ...       # checks, then runs command (after --)
```

**Exit codes** (stable contract):

| Code | Meaning |
|------|---------|
| 0 | Success (or nothing to do) |
| 1 | General validation error / GPU hard failure / bad config |
| 2 | Port owned by non-vLLM listener(s) |
| 3 | vLLM owned by different UID (blocked) |
| 4 | Listener found but not attributable (permissions/hidepid) |
| 5 | Attempted stop but port still listening |

**Environment variables**:

| Variable | Default | Description |
|----------|---------|-------------|
| `VLLM_HOST` | `127.0.0.1` | Bind address |
| `VLLM_PORT` | `8000` | Listen port |
| `VLLM_OWNER_REGEX` | _(built-in)_ | Regex to identify vLLM owner processes |
| `VLLM_DRY_RUN` | `0` | Report what would happen without sending signals |
| `VLLM_GPU_WARN_PCT` | `50` | Warn if GPU used% exceeds this (0..100) |
| `VLLM_SKIP_GPU_CHECK` | `0` | Skip GPU checks |
| `VLLM_REQUIRE_TORCH` | `0` | Require successful torch import |
| `VLLM_ALLOW_KILL_OTHER_UID` | `0` | Allow killing vLLM owned by other UIDs |
| `VLLM_PREFLIGHT_LOCKFILE` | `/tmp/vllm-preflight.lock` | Lock file path |
| `VLLM_TERM_GRACE` | `3` | Seconds to wait after SIGTERM before SIGKILL |
| `VLLM_PORT_FREE_TIMEOUT` | `10` | Seconds to wait for port to free |
| `VLLM_PORT_FREE_POLL` | `0.5` | Poll interval while waiting |
| `VLLM_PREFLIGHT_JSON` | `0` | Print single JSON object on stdout |

### `vllm-resolve-model`

Multi-source model provisioning with locking, atomic swaps, and per-model env files.

Searches configured sources in order and writes an env file that `vllm-serve` loads. The env file contains `_VLLM_RESOLVED_MODEL`, `VLLM_MODEL_PATH`, `HF_HOME`, and related vars.

**Sources** (searched in order):

| Source | Description |
|--------|-------------|
| `flox` | Model bundled in the Flox environment |
| `local` | Model already present in `$VLLM_MODELS_DIR/<model-name>` |
| `hf-cache` | HuggingFace hub cache at `$VLLM_MODELS_DIR/hub/` |
| `r2` | Cloudflare R2 bucket (requires `R2_BUCKET`, `R2_MODELS_PREFIX`) |
| `hf-hub` | Downloads from HuggingFace Hub (requires network access) |

**Required environment variables**:

| Variable | Description |
|----------|-------------|
| `VLLM_MODEL` | Model name (single safe path element, no `/` or `\`) |
| `VLLM_MODELS_DIR` | Base directory for local models and HF cache |

**Optional environment variables**:

| Variable | Default | Description |
|----------|---------|-------------|
| `VLLM_MODEL_ID` | _derived_ | Explicit HF model ID (`org/name`) |
| `VLLM_MODEL_ORG` | _(none)_ | Org prefix when deriving model ID |
| `VLLM_MODEL_SOURCES` | `flox,local,hf-cache,r2,hf-hub` | Comma-separated source order |
| `FLOX_ENV` | _(set by Flox)_ | Flox environment path (for `flox` source) |
| `FLOX_ENV_CACHE` | _(set by Flox)_ | Cache directory for env files |
| `VLLM_MODEL_ENV_FILE` | _derived_ | Override env file path |
| `R2_BUCKET` | _(none)_ | Cloudflare R2 bucket name |
| `R2_MODELS_PREFIX` | _(none)_ | R2 key prefix for models |
| `R2_ENDPOINT_URL` | _(none)_ | AWS CLI endpoint URL for R2 |
| `VLLM_RESOLVE_LOCK_TIMEOUT` | `300` | Seconds to wait for lock |
| `VLLM_SKIP_TOKENIZER_CHECK` | `0` | Skip tokenizer asset validation |
| `VLLM_KEEP_LOGS` | `0` | Keep logs on success (always kept on failure) |

**Env file output**: Written to `$FLOX_ENV_CACHE/vllm-model.<slug>.<hash>.env` with mode 600. The file exports `VLLM_MODEL`, `VLLM_MODEL_ID`, `_VLLM_RESOLVED_MODEL`, `_VLLM_RESOLVED_VIA`, and conditionally `HF_HOME` (when applicable) and `VLLM_MODEL_PATH` (when resolved from a local source).

### `vllm-serve`

Loads the resolved model env file and executes `vllm serve` with validated arguments. Reads static settings from `config.yaml` and builds the full argv from environment variables.

**Usage**:

```bash
vllm-serve                      # standard launch
vllm-serve --print-cmd          # print the vllm serve argv to stderr before exec
vllm-serve --dry-run            # print argv and exit (do not exec)
vllm-serve -- --extra-flag      # pass extra args through to vllm
```

**Required environment variables**:

Always required:

| Variable | Description |
|----------|-------------|
| `FLOX_ENV_PROJECT` | Project root (for config.yaml, unless `VLLM_CONFIG_FILE` is set) |
| `VLLM_TENSOR_PARALLEL_SIZE` | Must be > 0 |
| `VLLM_PIPELINE_PARALLEL_SIZE` | Must be > 0 |
| `VLLM_KV_CACHE_DTYPE` | Non-empty (e.g., `auto`, `fp8`) |
| `VLLM_MAX_MODEL_LEN` | Must be > 0 |
| `VLLM_MAX_NUM_BATCHED_TOKENS` | Must be > 0 |
| `VLLM_SERVED_MODEL_NAME` | Non-empty |

Required when `VLLM_MODEL_ENV_FILE` is not set (the standard case):

| Variable | Description |
|----------|-------------|
| `FLOX_ENV_CACHE` | Cache directory (used to derive the env file path) |
| `VLLM_MODEL_ID` | Full model ID (`org/model`), OR `VLLM_MODEL_ORG` + `VLLM_MODEL` |

**Optional environment variables**:

| Variable | Default | Description |
|----------|---------|-------------|
| `VLLM_MODEL_ENV_FILE` | _derived_ | Explicit env file path |
| `VLLM_PREFIX_CACHING` | `false` | Enable automatic prefix caching |
| `VLLM_CONFIG_FILE` | `$FLOX_ENV_PROJECT/config.yaml` | Override config path |
| `VLLM_ENV_FILE_TRUSTED` | `false` | Skip safe-mode env file validation |

**Safe env-file contract**: In safe mode (default), the env file must be a restricted `.env` subset — `KEY=VALUE` or `export KEY=VALUE` with optional quotes, no multiline values, no `${VAR}` interpolation, no command substitution. This matches `vllm-resolve-model` output.

## Quick start

### Consuming environment

```toml
# .flox/env/manifest.toml
version = 1

[install]
vllm-flox-runtime.pkg-path = "flox/vllm-flox-runtime"
vllm-python312-cuda12_9-sm120.pkg-path = "flox/vllm-python312-cuda12_9-sm120"
vllm-python312-cuda12_9-sm120.pkg-group = "vllm-python312-cuda12_9-sm120"

[hook]
on-activate = '''
  export VLLM_MODEL="${VLLM_MODEL:-Llama-3.1-8B-Instruct}"
  export VLLM_MODEL_ORG="${VLLM_MODEL_ORG:-meta-llama}"
  export VLLM_MODEL_SOURCES="${VLLM_MODEL_SOURCES:-local,hf-cache,hf-hub}"
  export VLLM_MODELS_DIR="${VLLM_MODELS_DIR:-$FLOX_ENV_PROJECT/models}"
  export VLLM_SERVED_MODEL_NAME="${VLLM_SERVED_MODEL_NAME:-$VLLM_MODEL}"

  export VLLM_HOST="${VLLM_HOST:-127.0.0.1}"
  export VLLM_PORT="${VLLM_PORT:-8000}"
  export VLLM_API_KEY="${VLLM_API_KEY:-sk-vllm-local-dev}"

  export VLLM_TENSOR_PARALLEL_SIZE="${VLLM_TENSOR_PARALLEL_SIZE:-1}"
  export VLLM_PIPELINE_PARALLEL_SIZE="${VLLM_PIPELINE_PARALLEL_SIZE:-1}"
  export VLLM_PREFIX_CACHING="${VLLM_PREFIX_CACHING:-false}"
  export VLLM_KV_CACHE_DTYPE="${VLLM_KV_CACHE_DTYPE:-auto}"
  export VLLM_MAX_MODEL_LEN="${VLLM_MAX_MODEL_LEN:-4096}"
  export VLLM_MAX_NUM_BATCHED_TOKENS="${VLLM_MAX_NUM_BATCHED_TOKENS:-4096}"

  export VLLM_LOGGING_LEVEL="${VLLM_LOGGING_LEVEL:-WARNING}"

  mkdir -p "$VLLM_MODELS_DIR"
'''

[services]
vllm.command = "vllm-preflight && vllm-resolve-model && vllm-serve"
```

Note: The vLLM Python/CUDA package (`vllm-python312-cuda12_9-sm120`) must be installed separately — swap the SM variant to match your GPU (e.g., `sm90` for H100, `sm89` for RTX 4090).

### Activate

```bash
flox activate --start-services

# Or override the model
VLLM_MODEL=DeepSeek-R1-Distill-Qwen-7B \
VLLM_MODEL_ORG=deepseek-ai \
  flox activate --start-services
```

## Service pipeline

The standard service command chains the three scripts:

```
vllm-preflight && vllm-resolve-model && vllm-serve
```

1. **vllm-preflight** — Reclaims the port if occupied by a stale vLLM process, checks GPU health via `nvidia-smi`, optionally verifies torch import
2. **vllm-resolve-model** — Provisions the model from configured sources, validates model directory (config, tokenizer, weight shards), writes a per-model env file
3. **vllm-serve** — Loads the env file, validates all required vars, builds the `vllm serve` argv from env vars + `config.yaml`, and `exec`s

## Building from source

```bash
cd build-vllm-flox-runtime
flox build
```

The build output lands in `./result-vllm-flox-runtime/`:

```
result-vllm-flox-runtime/
  bin/
    vllm-preflight
    vllm-resolve-model
    vllm-serve
  share/vllm-flox-runtime/
    vllm-flox-runtime-0.9.1       # Version marker
```

### Publishing

```bash
flox publish -o flox vllm-flox-runtime
```

## Architecture

This package is part of a composable vLLM stack:

```
┌──────────────────────────────────────────────────────┐
│  Consuming Environment                               │
│                                                      │
│  [install]                                           │
│    flox/vllm-flox-runtime       # this package       │
│    flox/vllm-python312-cuda*    # vLLM + CUDA        │
│    (optional) flox/vllm-flox-monitoring              │
│                                                      │
│  [services]                                          │
│    vllm → vllm-preflight                             │
│           && vllm-resolve-model                      │
│           && vllm-serve                              │
│                                                      │
│  ┌─────────────────────────────────────────────────┐ │
│  │  vllm-preflight                                 │ │
│  │    Port reclaim ← /proc/net/tcp + /proc/<pid>/  │ │
│  │    GPU health   ← nvidia-smi                    │ │
│  ├─────────────────────────────────────────────────┤ │
│  │  vllm-resolve-model                             │ │
│  │    Sources: flox → local → hf-cache → r2 → hub │ │
│  │    Output: per-model .env file                  │ │
│  ├─────────────────────────────────────────────────┤ │
│  │  vllm-serve                                     │ │
│  │    Loads .env → validates args → exec vllm serve│ │
│  └─────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

## Repo structure

```
build-vllm-flox-runtime/
  .flox/
    env/manifest.toml                    # Minimal build manifest
    pkgs/vllm-flox-runtime.nix           # Nix derivation
  scripts/
    vllm-preflight                       # Pre-flight validation (585 lines)
    vllm-resolve-model                   # Model provisioning (736 lines)
    vllm-serve                           # Validated serving (367 lines)
  .gitignore
  README.md
```
