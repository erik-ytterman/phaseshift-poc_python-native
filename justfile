# List recipes; hint if the venv is active but tab completion isn't
# (e.g. activated with `source .venv/bin/activate` instead of activate.sh)
default:
    @just --list
    @if [ -n "${VIRTUAL_ENV:-}" ] && [ -z "${JUST_COMPLETION_REGISTERED:-}" ]; then \
        echo "hint: venv is active but just tab completion is not; run: source ./activate.sh" >&2; \
    fi

# Install deps and build the Rust extension
setup:
    uv sync
    just dev

# Rebuild the Rust extension into the venv
dev:
    uv run maturin develop --uv

fmt:
    uv run ruff format .
    cargo fmt

lint:
    uv run ruff check .
    uv run ruff format --check .
    cargo fmt --check
    cargo clippy -- -D warnings

typecheck:
    uv run mypy

test: dev
    cargo test
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

build:
    uv run maturin build --release

