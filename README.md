# python-native

A Python package with a native core written in Rust, built with
[PyO3](https://pyo3.rs) and [maturin](https://www.maturin.rs), managed by
[uv](https://docs.astral.sh/uv/). Ruff, mypy, pytest, py-spy and
[just](https://just.systems) are installed as project dev tools.

The distribution name is `python-native`; the import name is `python_native`.

---

## Prerequisites

Only uv and the Rust toolchain are needed. Everything else (including `just`)
is installed by uv into the project venv.

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

## Creating a new project

Use the scaffold script `new-pyrust.sh`:

```bash
new-pyrust python-native phaseshift-poc_python-native   # name, directory
```

It runs `uv init --lib --build-backend maturin`, adds the dev tools and
configuration below, writes the `justfile`, extends `.gitignore`, adds a smoke
test, and finishes with `just setup` and `just check`.

To do it by hand:

```bash
uv init --lib --build-backend maturin --name python-native phaseshift-poc_python-native
cd phaseshift-poc_python-native
uv add --dev ruff mypy py-spy pytest maturin rust-just
```

then add the configuration and `justfile` shown below.

## Daily workflow

```bash
source ./activate.sh           # activate the venv + enable `just` tab completion
just                           # list recipes
deactivate                     # leave the venv
```

Without activating, prefix commands with `uv run` (e.g. `uv run just check`).

There is no separate rebuild step: every `uv run` (which the recipes use)
rebuilds the Rust extension if a `.rs` file changed.

| Recipe | What it does |
|---|---|
| `just setup` | `uv sync` (installs deps, builds the Rust extension) |
| `just fmt` | Format Python (Ruff) and Rust (`cargo fmt`) |
| `just lint` | Ruff, format checks, `cargo clippy -D warnings` |
| `just typecheck` | mypy (strict) |
| `just test` | `cargo test` + `pytest` |
| `just check` | `lint` + `typecheck` + `test` |
| `just profile <script>` | py-spy flame graph incl. Rust frames → `profile.svg` |
| `just build` | Release wheel into `target/wheels/` |
| `just clean` | Remove venv, build output and caches |

---

## Project layout

```
phaseshift-poc_python-native/
├── pyproject.toml          Python project definition + tool config
├── uv.lock                 exact Python dependency versions (commit it)
├── .python-version         Python version uv uses
├── Cargo.toml              Rust crate definition
├── Cargo.lock              exact Rust dependency versions (commit it)
├── justfile                task shortcuts
├── activate.sh             activate venv + just completion (source it)
├── .gitignore
├── README.md
├── src/
│   ├── lib.rs              Rust source → compiled to python_native._core
│   └── python_native/
│       ├── __init__.py     public Python API, wraps _core
│       ├── _core.pyi       type signatures for the Rust module
│       └── py.typed        marker: package ships type information
├── tests/
│   └── test_*.py           pytest tests
└── examples/
    └── *.py                runnable demos
```

The Rust code is a **private core** (`_core`, leading underscore = "don't
import directly"); users only import the **public package** `python_native`.

### Which names are fixed?

- **Required by a tool or standard:** `pyproject.toml`, `uv.lock`,
  `.python-version`, `Cargo.toml`, `Cargo.lock`, `justfile`, `.gitignore`,
  `__init__.py`, `py.typed`, `__main__.py` (if used).
- **Conventions, changeable in config:** the `src/` layout, `src/lib.rs`,
  the `_core` module name, `tests/`, and pytest's `test_*.py` / `test_*`
  discovery rules.
  - `_core` must match in three places: `[lib] name` in `Cargo.toml`,
    `mod _core` in `lib.rs`, and `module-name` in `[tool.maturin]`.
  - A `.pyi` stub must have the same name as its module.
- **Arbitrary:** function names, test file names after `test_`, and
  `examples/`.

---

## Adding a native function

Four files change every time.

**1. Rust implementation — `src/lib.rs`**

Keep the logic in a plain Rust function so `cargo test` can test it without
Python; add a thin `#[pyfunction]` wrapper inside `mod _core`. Doc comments
(`///`) become the Python `__doc__`.

```rust
use pyo3::prelude::*;

fn factor_impl(mut n: u64) -> Vec<u64> {
    let mut factors = Vec::new();
    let mut d = 2;
    while d <= n / d {
        while n.is_multiple_of(d) {
            factors.push(d);
            n /= d;
        }
        d += 1;
    }
    if n > 1 {
        factors.push(n);
    }
    factors
}

#[pymodule]
mod _core {
    use pyo3::prelude::*;

    /// Return the prime factors of `n` in ascending order.
    ///
    /// `n` must be in the range 0 <= n < 2**64; otherwise OverflowError is raised.
    #[pyfunction]
    fn factor(n: u64) -> Vec<u64> {
        super::factor_impl(n)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn factors() {
        assert_eq!(factor_impl(12), vec![2, 2, 3]);
        assert_eq!(factor_impl(1), Vec::<u64>::new());
    }
}
```

**2. Type stub — `src/python_native/_core.pyi`**

```python
def factor(n: int) -> list[int]: ...
```

**3. Public API — `src/python_native/__init__.py`**

Wrap each native function in a plain Python function. The wrapper keeps the
public name and signature independent of the Rust side, and carries its own
docstring (the Rust `__doc__` stays on `_core.factor`).

```python
from python_native import _core


def factor(n: int) -> list[int]:
    """Return the prime factors of `n` in ascending order."""
    return _core.factor(n)
```

**4. Test — `tests/test_factor.py`**

```python
import pytest

import python_native


def test_factor() -> None:
    assert python_native.factor(12) == [2, 2, 3]


def test_factor_edge_cases() -> None:
    assert python_native.factor(0) == []
    assert python_native.factor(1) == []


def test_factor_negative() -> None:
    with pytest.raises(OverflowError):
        python_native.factor(-5)
```

**5. Build, install and verify**

```bash
just check
uv run python -c "import python_native; print(python_native.factor(360))"
```

### Type mapping

PyO3 converts types at the boundary. Some common mappings:

| Rust | Python stub |
|---|---|
| `i64`, `u64`, `usize` | `int` |
| `f64` | `float` |
| `bool` | `bool` |
| `String` / `&str` | `str` |
| `Vec<T>` | `list[T]` (copied in and out) |
| `HashMap<K, V>` | `dict[K, V]` |
| `Option<T>` | `T \| None` |
| `PyResult<T>` | `T` (an `Err` raises an exception) |

A Python `int` is unbounded, so values that don't fit the Rust type raise at
runtime even though mypy accepts the call. For `u64`, negative values and
values ≥ 2⁶⁴ raise `OverflowError`; a `float` raises `TypeError`. Document
the valid range in the docstring.

---

## How it works

### Editable install

`uv sync` and `uv run` install the package into `.venv` in
**editable** mode (PEP 660). Instead of copying the package into
`site-packages`, they write a single pointer file:

```
.venv/lib/python3.x/site-packages/python_native.pth   → ~/path/to/phaseshift-poc_python-native/src
```

Python adds that path to `sys.path` at startup, so imports resolve to your
real source folder. The build also places the compiled extension next to
your Python code:

```
src/python_native/_core.abi3.so     (.pyd on Windows)
```

That is how scripts in `examples/` and `tests/` find the package: through
the venv, not their location on disk.

| You edit | Takes effect |
|---|---|
| `.py` files | Immediately (read from `src/`) |
| `.pyi` stubs | Next mypy run |
| `.rs` files | Next `uv run` or `uv sync` (rebuilds on change) |

It only works with the venv's Python: a system `python3` has no `.pth` file
and gives `ModuleNotFoundError`.

### Install vs build

| Command | Compiles Rust | Installs into `.venv` | Output |
|---|---|---|---|
| `uv sync` / `uv run` | If changed | Yes, editable | `.pth` + `.so` in `src/` |
| `just build` / `uv build` | Yes | **No** | Wheel for distribution |

A wheel is self-contained: it copies the package and `.so` into the target
`site-packages`, with no link back to your source.

### Stub files (`.pyi`)

A `.pyi` file contains only type signatures (`...` as body). Type checkers
and editors read it instead of the compiled `.so`, which they cannot
inspect. Python ignores `.pyi` files at runtime. **It is not generated from
Rust — keep it in sync by hand** whenever a `#[pyfunction]` changes.

---

## Configuration

### `pyproject.toml` (additions)

```toml
[tool.ruff]
line-length = 100
target-version = "py313"   # match requires-python

[tool.ruff.lint]
select = ["E", "F", "I", "B", "UP", "SIM", "RUF"]

[tool.mypy]
strict = true
files = ["src/python_native", "tests"]
mypy_path = "src"
explicit_package_bases = true

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = ["--import-mode=importlib"]
```

uv's template already provides `[tool.maturin]` (with `module-name`,
`python-source = "src"`) and `[tool.uv] cache-keys` that include
`src/**/*.rs`, which is why `uv run` rebuilds after Rust edits. Add one
setting to it:

```toml
[tool.uv]
# Build in the project venv: an isolated build env gets a new path every time,
# which makes pyo3 recompile from scratch on each Rust change
no-build-isolation-package = ["python-native"]
```

### Avoiding needless recompiles

pyo3's build script tells cargo to rebuild pyo3 whenever certain environment
variables change (`PYO3_PYTHON`, `PYO3_ENVIRONMENT_SIGNATURE`, `VIRTUAL_ENV`,
…). maturin sets them; plain `cargo` doesn't. Two things keep builds
incremental:

- `no-build-isolation-package` (above) gives uv's builds a stable
  environment, so a Rust edit recompiles only this crate (~0.5 s instead of
  ~10 s).
- The `justfile` runs `cargo clippy` and `cargo test` with
  `CARGO_TARGET_DIR=target/cargo`, so they don't invalidate maturin's
  artifacts in `target/` and vice versa.

Don't mix in `maturin develop`: it builds into the same venv with different
settings, and the next `uv run` replaces its install anyway.

### `justfile`

```just
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

```

### `.gitignore` (additions to uv's template)

uv's template is Python-only and omits Rust build output.

```gitignore
# Rust build output
/target

# Compiled extension placed in the package by the editable build
src/python_native/*.so
src/python_native/*.pyd

# py-spy output
profile.svg

# Tool caches
.mypy_cache/
.ruff_cache/
.pytest_cache/
```

Keep `Cargo.lock` and `uv.lock` committed. If `target/` was already
committed: `git rm -r --cached target`.

---

## Activating the venv and `just` completion

`just` is installed only in the project venv (`rust-just` dev dependency),
and `rust-just` ships only the binary, so the shell has no completion for it
by default. The project-local `activate.sh` handles both, without touching
any file outside the project:

```bash
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
```

```bash
source ./activate.sh       # from the project root
just <TAB><TAB>            # lists the recipes
```

- **Order matters:** the venv is activated first, so `just` is on PATH when
  the completion is registered.
- Works from any directory (`source ~/path/to/phaseshift-poc_python-native/activate.sh`); the
  project is located relative to the script.
- Recreates a missing venv (e.g. after `just clean`) with `uv sync`.
- Must be **sourced**, not executed (`./activate.sh` prints a hint and
  exits), otherwise the activation only applies to a subshell.
- Completion lives only in the current shell; it is gone after closing the
  terminal or opening a new one.
- Bash only (`BASH_SOURCE`, `JUST_COMPLETE=bash`).
- Exports `JUST_COMPLETION_REGISTERED=1`. If the venv is active without it
  (e.g. activated with `source .venv/bin/activate`), plain `just` prints a
  hint to source `activate.sh`. The variable is inherited by child shells
  while the completion is not, so a nested `bash` gets no hint.

### Why not in `~/.bashrc`?

Newer `just` versions print only a one-liner for
`just --completions bash`:

```bash
eval "$(JUST_COMPLETE=bash just)"
```

That line runs `just` when it is loaded. At shell startup no venv is active,
so `just` is not found and no completion is registered. `activate.sh` runs
it *after* activation, which is why it works there.

Bash only reads startup files from your home directory, so activating
automatically when a terminal opens always needs one line outside the
project. If you want that, add to `~/.bashrc`:

```bash
[ -f ~/path/to/phaseshift-poc_python-native/activate.sh ] && source ~/path/to/phaseshift-poc_python-native/activate.sh
```

### Notes

- `uv run just <TAB>` completes uv's arguments, not just's.
- Works across multiple projects: each project's `activate.sh` uses that
  project's `just`, and recipes are read from the `justfile` in the current
  directory.

Diagnose with:

```bash
type just              # on PATH? should be .venv/bin/just
complete -p just       # completion registered? should show _clap_complete_just
just --summary         # justfile found?
```

---

## Validating the setup

1. **Tools:** `uv run just --version`, `uv run ruff --version`, etc.
2. **Build and import:** `just setup`, then
   `uv run python -c "import python_native"`.
3. **Checks pass:** `just check`.
4. **Checks catch errors** — break things on purpose and revert:

   | Introduce | Expect failure from |
   |---|---|
   | Unused `import os` | `just lint` (Ruff F401) |
   | `x: int = "a"` | `just typecheck` |
   | Function missing from `_core.pyi` | `just typecheck` |
   | `let unused = 5;` in Rust | `just lint` (clippy) |
   | `assert False` in a test | `just test` |

5. **Clean rebuild:**

   ```bash
   deactivate
   uv run just clean
   uv run just setup && uv run just check && uv run just build
   ```

   Or `git clean -xdn` (dry run) / `git clean -xdf` to delete everything
   untracked.

6. **Fresh clone** — proves everything needed is committed:

   ```bash
   cd /tmp && rm -rf fresh && git clone <repo> fresh && cd fresh
   uv run just setup && uv run just check
   ```

---

## Performance notes

- **Builds are already optimized.** maturin's build backend, which `uv run`
  uses, compiles with the `release` profile, so benchmark directly:

  ```bash
  uv run python examples/do_factorize.py 10000000000000061   # a 17-digit prime, ~1.5 s
  ```

  `cargo test` and `cargo clippy` use the debug profile; that only affects
  Rust-side tests.
- **Crossing the boundary costs.** Converting a large Python list to a
  `Vec` copies every element. Rust pays off when it does real work per item,
  or with NumPy arrays via `rust-numpy` (zero-copy).
- Release the GIL during long Rust computations with `py.detach(...)`
  (named `allow_threads` before PyO3 0.26).
- On macOS, `py-spy` needs `sudo`.

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| mypy: `Duplicate module named "__main__"` | Same filename in `tests/` and the package; `tests/` isn't a package | Rename test files to `test_*.py`; set `mypy_path` + `explicit_package_bases` |
| mypy: `tests: Cannot read file` | Path in `files` doesn't exist | Create `tests/` or remove it from `files` |
| `target/` shows up in git | uv's `.gitignore` is Python-only | Add `/target` |
| `just <TAB>` does nothing, or only completes file names | Completion not registered in this shell, e.g. venv activated with `.venv/bin/activate` (`just` prints a hint) | `source ./activate.sh`; verify with `complete -p just` (see *Activating the venv*) |
| `just` disappears after `uv sync` | `rust-just` not declared; `uv sync` removes undeclared packages | `uv add --dev rust-just` |
| `ModuleNotFoundError: python_native` | Not using the venv's Python | `uv run python ...` or `source ./activate.sh` |
| Prompt shows the venv but commands fail | `.venv` deleted (e.g. `just clean`) while active | `deactivate`, then `source ./activate.sh` |
| Rust change not visible | Ran `python` in the activated venv, which doesn't rebuild | `uv run python ...` or `uv sync` |

