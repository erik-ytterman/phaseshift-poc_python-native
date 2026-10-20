#!/usr/bin/env bash
# Scaffold a Python package with a native Rust core (PyO3 + maturin, managed by uv).
# Usage: new-pyrust.sh [--python X.Y] <name> [directory]
set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") [--python X.Y] <name> [directory]" >&2
    exit 2
}

python_version="3.13"
args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --python) [[ $# -ge 2 ]] || usage; python_version="$2"; shift 2 ;;
        -h | --help) usage ;;
        -*) echo "Unknown option: $1" >&2; usage ;;
        *) args+=("$1"); shift ;;
    esac
done
[[ ${#args[@]} -ge 1 && ${#args[@]} -le 2 ]] || usage

name="${args[0]}"
dir="${args[1]:-$name}"
module="${name//-/_}"
py_tag="py${python_version//./}" # 3.13 -> py313

[[ "$python_version" =~ ^3\.[0-9]+$ ]] || { echo "Invalid --python: $python_version" >&2; exit 2; }
[[ -e "$dir" ]] && { echo "Already exists: $dir" >&2; exit 1; }
for tool in uv cargo; do
    command -v "$tool" >/dev/null || { echo "Missing prerequisite: $tool" >&2; exit 1; }
done

# An active venv from another project would confuse uv
unset VIRTUAL_ENV

uv init --lib --build-backend maturin --python "$python_version" --name "$name" "$dir"
cd "$dir"
uv add --dev ruff mypy py-spy pytest maturin rust-just

# --- Cargo.toml: stable ABI matching requires-python ---------------------
sed -i -E \
    -e "s/abi3-py[0-9]+/abi3-$py_tag/" \
    -e "s/minimum Python version 3\.[0-9]+/minimum Python version $python_version (matches requires-python)/" \
    Cargo.toml

# --- pyproject.toml --------------------------------------------------------
sed -i 's|^\[tool\.uv\]$|[tool.uv]\
# Build in the project venv: an isolated build env gets a new path every time,\
# which makes pyo3 recompile from scratch on each Rust change\
no-build-isolation-package = ["'"$name"'"]|' pyproject.toml

cat >>pyproject.toml <<EOF

[tool.ruff]
line-length = 100
target-version = "$py_tag"

[tool.ruff.lint]
select = ["E", "F", "I", "B", "UP", "SIM", "RUF"]

[tool.mypy]
strict = true
files = ["src/$module", "tests"]
mypy_path = "src"
explicit_package_bases = true

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = ["--import-mode=importlib"]
EOF

# --- Python API: wrap the native functions ---------------------------------
cat >"src/$module/__init__.py" <<EOF
from $module import _core


def hello() -> str:
    """Return a greeting from the Rust core."""
    return _core.hello_from_bin()
EOF

mkdir -p tests
cat >tests/test_smoke.py <<EOF
import $module


def test_hello() -> None:
    assert isinstance($module.hello(), str)
EOF

# --- .gitignore ------------------------------------------------------------
cat >>.gitignore <<EOF

# Rust build output
/target

# Compiled extension placed in the package by the editable build
src/$module/*.so
src/$module/*.pyd

# py-spy output
profile.svg

# Tool caches
.mypy_cache/
.ruff_cache/
.pytest_cache/
EOF

# --- justfile --------------------------------------------------------------
cat >justfile <<'EOF'
# List recipes; hint if the venv is active but tab completion isn't
# (e.g. activated with `source .venv/bin/activate` instead of activate.sh)
default:
    @just --list
    @if [ -n "${VIRTUAL_ENV:-}" ] && [ -z "${JUST_COMPLETION_REGISTERED:-}" ]; then \
        echo "hint: venv is active but just tab completion is not; run: source ./activate.sh" >&2; \
    fi

# Plain cargo gets its own target dir: pyo3 rebuilds whenever env vars that
# maturin/uv set change, so sharing target/ with them recompiles every switch
cargo_target := "target/cargo"

# Install deps and build the Rust extension (`uv run` rebuilds it on change)
setup:
    uv sync

fmt:
    uv run ruff format .
    cargo fmt

lint:
    uv run ruff check .
    uv run ruff format --check .
    cargo fmt --check
    CARGO_TARGET_DIR={{cargo_target}} cargo clippy -- -D warnings

typecheck:
    uv run mypy

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

build:
    uv run maturin build --release
EOF

# --- activate.sh -----------------------------------------------------------
cat >activate.sh <<'EOF'
# Activate the project venv and enable just tab completion (bash).
# Usage: source ./activate.sh
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "Run this with: source ${0}" >&2
    exit 1
fi

_project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$_project_dir/.venv" ]]; then
    (cd "$_project_dir" && uv sync)
fi

source "$_project_dir/.venv/bin/activate"
eval "$(JUST_COMPLETE=bash just)"
# Marker for the justfile's `default` recipe: completion is registered in this shell.
export JUST_COMPLETION_REGISTERED=1
unset _project_dir
EOF

# --- Build and verify ------------------------------------------------------
uv run just setup
uv run just check

echo
echo "Created $dir. Next: cd $dir && source ./activate.sh"
