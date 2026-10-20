#!/usr/bin/env bash
# Scaffold a Python package with a native Rust core (PyO3 + maturin, managed by uv).
# Usage: new-pyrust.sh [--python X.Y] <name> [directory]
set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") [--python X.Y] <name> [directory]" >&2
    exit "${1:-2}"
}

python_version="3.13"
args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --python) [[ $# -ge 2 ]] || usage; python_version="$2"; shift 2 ;;
        -h | --help) usage 0 ;;
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
# uv normalizes other names (My.Pkg -> my-pkg), which would break the paths below
[[ "$name" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]] ||
    { echo "Invalid name: $name (use lowercase letters, digits and single hyphens)" >&2; exit 2; }
[[ -e "$dir" ]] && { echo "Already exists: $dir" >&2; exit 1; }
for tool in uv cargo git; do
    command -v "$tool" >/dev/null || { echo "Missing prerequisite: $tool" >&2; exit 1; }
done

# This repo is the template for the project-independent files
template_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# An active venv from another project would confuse uv
unset VIRTUAL_ENV

# The new project is standalone: --no-workspace keeps uv from adding it as a
# member of an enclosing project, and it gets its own git repo even when
# created inside another one (uv init skips git init there)
uv init --lib --build-backend maturin --no-workspace \
    --python "$python_version" --name "$name" "$dir"
cd "$dir"
[[ -d .git ]] || git init -q
uv add --dev ruff mypy py-spy pytest maturin rust-just

# --- Cargo.toml: stable ABI matching requires-python, no extension-module ----
sed -i -E \
    -e '/^# "extension-module" tells/c\
# No "extension-module" feature: maturin sets PYO3_BUILD_EXTENSION_MODULE instead, so the\
# extension doesn'"'"'t link libpython but `cargo test` binaries can (needed to call Python from Rust tests)' \
    -e 's/"extension-module", //' \
    -e "s/abi3-py[0-9]+/abi3-$py_tag/" \
    -e "s/minimum Python version 3\.[0-9]+/minimum Python version $python_version (matches requires-python)/" \
    Cargo.toml

# --- pyproject.toml --------------------------------------------------------
# maturin sets PYO3_BUILD_EXTENSION_MODULE, which replaces the extension-module feature
sed -i 's/"maturin>=1\.0,<2\.0"/"maturin>=1.15,<2.0"/' pyproject.toml
sed -i 's|^\[tool\.uv\]$|[tool.uv]\
# Build in the project venv: an isolated build env gets a new path every time,\
# which makes pyo3 recompile from scratch on each Rust change\
no-build-isolation-package = ["'"$name"'"]|' pyproject.toml

# Fail loudly if the uv template changed and an edit above matched nothing
for check in "Cargo.toml:abi3-$py_tag" 'pyproject.toml:"maturin>=1.15,<2.0"' \
    'pyproject.toml:no-build-isolation-package'; do
    grep -qF "${check#*:}" "${check%%:*}" ||
        { echo "${check%%:*} edit failed (${check#*:}); has uv's template changed?" >&2; exit 1; }
done
if grep -q 'features = .*"extension-module"' Cargo.toml; then
    echo "Cargo.toml edit failed (extension-module); has uv's template changed?" >&2
    exit 1
fi

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

# --- justfile and activate.sh: project-independent, copied from this repo ---
cp "$template_dir/justfile" "$template_dir/activate.sh" .

# --- Build and verify ------------------------------------------------------
uv run just check

echo
echo "Created $dir. Next: cd $dir && source ./activate.sh"
