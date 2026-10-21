# List recipes (and hint if tab completion is missing)
default:
    @just --list
    @# VIRTUAL_ENV_PROMPT is set by activating the venv, not by `uv run`
    @if [ -n "${VIRTUAL_ENV_PROMPT:-}" ] && [ -z "${JUST_COMPLETION_REGISTERED:-}" ]; then \
        echo "hint: venv is active but just tab completion is not; run: source ./activate.sh" >&2; \
    fi

# Plain cargo gets its own target dir: pyo3 rebuilds whenever env vars that
# maturin/uv set change, so sharing target/ with them recompiles every switch
cargo_target := "target/cargo"

# Format Python and Rust
fmt:
    uv run ruff format .
    cargo fmt

# Lint and check formatting (Python and Rust)
lint:
    uv run ruff check .
    uv run ruff format --check .
    cargo fmt --check
    CARGO_TARGET_DIR={{cargo_target}} uv run cargo clippy --all-targets -- -D warnings

# Type-check Python (mypy strict)
typecheck:
    uv run mypy

# Run Rust and Python tests. cargo test binaries may link libpython, which
# uv's Python keeps in its own lib/ directory, outside the loader's search path
test:
    LD_LIBRARY_PATH="$(uv run python -c 'import sysconfig; print(sysconfig.get_config_var("LIBDIR"))')${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        CARGO_TARGET_DIR={{cargo_target}} uv run cargo test
    uv run pytest

# Remove build output, caches and the venv (keeps the compiled extension in src/)
clean:
    @# uv reinstalls the editable build from its cache, and that wheel only holds
    @# the .pth file: without the .so in src/, nothing would rebuild it
    rm -rf .venv target dist .mypy_cache .ruff_cache .pytest_cache
    rm -f profile.svg
    find . -name __pycache__ -type d -prune -exec rm -rf {} +

# Run every check (good for CI / pre-push)
check: lint typecheck test

# Profile a script (with its arguments), including Rust frames
profile script *args:
    uv run py-spy record --native -o profile.svg -- python "{{script}}" {{args}}

# Build a release wheel (manylinux-tagged) into dist/
build:
    uv run maturin build --release --out dist
