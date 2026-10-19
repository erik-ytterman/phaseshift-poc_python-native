default:
    @just --list

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
    cargo clippy -- -D warnings

typecheck:
    uv run mypy

test: dev
    cargo test
    uv run pytest

# Run every check (good for CI / pre-push)
check: lint typecheck test

# Profile a script, including Rust frames
profile script:
    uv run py-spy record --native -o profile.svg -- python {{script}}

build:
    uv run maturin build --release

