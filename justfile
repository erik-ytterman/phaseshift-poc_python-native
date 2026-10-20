# List recipes (and hint if tab completion is missing)
default:
    @just --list
    @if [ -n "${VIRTUAL_ENV:-}" ] && [ -z "${JUST_COMPLETION_REGISTERED:-}" ]; then \
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
    CARGO_TARGET_DIR={{cargo_target}} cargo clippy -- -D warnings

# Type-check Python (mypy strict)
typecheck:
    uv run mypy

# Run Rust and Python tests
test:
    CARGO_TARGET_DIR={{cargo_target}} cargo test
    uv run pytest

# Remove all build artifacts and the venv
clean:
    rm -rf .venv target dist .mypy_cache .ruff_cache .pytest_cache
    find src -name '*.so' -delete -o -name '*.pyd' -delete
    rm -f profile.svg
    find . -name __pycache__ -type d -prune -exec rm -rf {} +

# Run every check (good for CI / pre-push)
check: lint typecheck test

# Profile a script, including Rust frames
profile script:
    uv run py-spy record --native -o profile.svg -- python {{script}}

# Build a release wheel into target/wheels/
build:
    uv run maturin build --release

