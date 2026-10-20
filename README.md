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

## Daily workflow

```bash
source ./activate.sh           # activate the venv + enable `just` tab completion
just                           # list recipes
just check                     # lint, type-check and test everything
deactivate                     # leave the venv
```

Without activating, prefix commands with `uv run` (e.g. `uv run just check`).

There is no separate build step: every `uv run` (which the recipes use)
installs dependencies and rebuilds the Rust extension if a `.rs` file
changed.

| Recipe | What it does |
|---|---|
| `just fmt` | Format Python (Ruff) and Rust (`cargo fmt`) |
| `just lint` | Ruff, format checks, `cargo clippy -D warnings` |
| `just typecheck` | mypy (strict) |
| `just test` | `cargo test` + `pytest` |
| `just check` | `lint` + `typecheck` + `test` |
| `just profile <script>` | py-spy flame graph incl. Rust frames → `profile.svg` |
| `just build` | Release wheel into `target/wheels/` |
| `just clean` | Remove venv, build output and caches |

## Creating a new project

[`scripts/new-pyrust.sh`](scripts/new-pyrust.sh) creates a project like
this one:

```bash
scripts/new-pyrust.sh my-pkg                     # directory defaults to the name
scripts/new-pyrust.sh --python 3.14 my-pkg ~/x   # Python version (default 3.13), directory
```

It starts from `uv init --lib --build-backend maturin`, adds the dev tools
and the configuration described below, copies `justfile` and `activate.sh`
from this repo, and finishes with `just check`. The result is standalone,
with its own venv and git repo and no reference to this repo, even when
created inside it; later changes here don't affect it.

Requirements: uv, cargo and git, and GNU `sed` (Linux). Run the script from
a checkout of this repo, since that is where it copies the two files from;
the current directory doesn't matter.

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
├── src/
│   ├── lib.rs              Rust source → compiled to python_native._core
│   └── python_native/
│       ├── __init__.py     public Python API, wraps _core
│       ├── _core.pyi       type signatures for the Rust module
│       └── py.typed        marker: package ships type information
├── tests/                  pytest tests (test_*.py)
├── examples/               runnable demos
└── scripts/
    └── new-pyrust.sh       scaffolds a new project like this one
```

The Rust code is a **private core** (`_core`, leading underscore = "don't
import directly"); users only import the **public package** `python_native`.

The name `_core` must match in three places: `[lib] name` in `Cargo.toml`,
`mod _core` in `lib.rs`, and `module-name` in `[tool.maturin]`. Its stub
must be named `_core.pyi`.

---

## Adding a native function

Four files change every time. Using `factor` as the example:

**1. Rust — [`src/lib.rs`](src/lib.rs).** Keep the logic in a plain Rust
function so `cargo test` can test it without Python, and add a thin
`#[pyfunction]` inside `mod _core`:

```rust
fn factor_impl(mut n: u64) -> Vec<u64> {
    // ...
}

#[pymodule]
mod _core {
    use pyo3::prelude::*;

    /// Return the prime factors of `n` in ascending order.
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
    }
}
```

**2. Type stub — [`src/python_native/_core.pyi`](src/python_native/_core.pyi).**
Type checkers can't inspect the compiled `.so`, so declare the signature by
hand:

```python
def factor(n: int) -> list[int]: ...
```

**3. Public API — [`src/python_native/__init__.py`](src/python_native/__init__.py).**
Wrap the native function in a plain Python function. This keeps the public
name and signature independent of the Rust side. The wrapper needs its own
docstring, because the Rust `///` comment ends up on `_core.factor`.

```python
from python_native import _core


def factor(n: int) -> list[int]:
    """Return the prime factors of `n` in ascending order."""
    return _core.factor(n)
```

**4. Test — [`tests/test_factor.py`](tests/test_factor.py).**

```python
import python_native


def test_factor() -> None:
    assert python_native.factor(12) == [2, 2, 3]
```

Then run `just check`.

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

`uv sync` and `uv run` install the package into `.venv` in **editable**
mode (PEP 660). Instead of copying the package into `site-packages`, they
write a single pointer file:

```
.venv/lib/python3.x/site-packages/python_native.pth   → <project>/src
```

Python adds that path to `sys.path` at startup, so imports resolve to your
source folder. The build places the compiled extension next to your Python
code, as `src/python_native/_core.abi3.so` (`.pyd` on Windows). That is how
`examples/` and `tests/` find the package: through the venv, not their
location on disk.

| You edit | Takes effect |
|---|---|
| `.py` files | Immediately (read from `src/`) |
| `.pyi` stubs | Next mypy run |
| `.rs` files | Next `uv run` or `uv sync` (rebuilds on change) |

It only works with the venv's Python: a system `python3` gives
`ModuleNotFoundError`.

### Install vs build

| Command | Compiles Rust | Installs into `.venv` | Output |
|---|---|---|---|
| `uv sync` / `uv run` | If changed | Yes, editable | `.pth` + `.so` in `src/` |
| `just build` / `uv build` | Yes | **No** | Wheel for distribution |

A wheel is self-contained: it copies the package and `.so` into the target
`site-packages`, with no link back to your source.

### Avoiding needless recompiles

pyo3's build script tells cargo to rebuild pyo3 whenever certain environment
variables change (`PYO3_PYTHON`, `PYO3_ENVIRONMENT_SIGNATURE`, `VIRTUAL_ENV`,
…). maturin sets them; plain `cargo` doesn't. Two settings keep builds
incremental:

- `no-build-isolation-package` in `pyproject.toml` makes uv build in the
  project venv. An isolated build env gets a new path every time, which
  would recompile pyo3 on every Rust edit (~10 s instead of ~0.5 s).
- The `justfile` runs `cargo clippy` and `cargo test` with
  `CARGO_TARGET_DIR=target/cargo`, so they don't invalidate uv's build in
  `target/` and vice versa.

Don't use `maturin develop`: it installs a second build with different
settings, and the next `uv run` replaces it anyway.

---

## Configuration

What this project adds to uv's maturin template:

- **[`pyproject.toml`](pyproject.toml):** `[tool.ruff]`, `[tool.mypy]`
  (strict, covering `src/python_native` and `tests`) and
  `[tool.pytest.ini_options]`. `[tool.uv]` gets
  `no-build-isolation-package` (see above). The template already has
  `cache-keys` covering `src/**/*.rs`, which is why `uv run` rebuilds after
  Rust edits.
- **[`Cargo.toml`](Cargo.toml):** the stable-ABI feature is `abi3-py313`
  to match `requires-python` (the template has `abi3-py39`).
- **[`justfile`](justfile):** the recipes above.
- **[`activate.sh`](activate.sh):** see the next section.
- **[`.gitignore`](.gitignore):** Rust build output (`/target`), the
  compiled extension in `src/`, `profile.svg` and tool caches. uv's
  template only covers Python.

Keep `Cargo.lock` and `uv.lock` committed.

---

## Activating the venv and `just` completion

`just` is installed only in the project venv (the `rust-just` dev
dependency), and `rust-just` ships only the binary, so the shell has no tab
completion for it. [`activate.sh`](activate.sh) handles both without
touching any file outside the project:

```bash
source ./activate.sh       # from the project root
just <TAB><TAB>            # lists the recipes
```

- It activates the venv first, then registers completion with
  `eval "$(JUST_COMPLETE=bash just)"`. The order matters: that line runs
  `just`, which must already be on `PATH`. This is also why the line can't
  go in `~/.bashrc`: no venv is active at shell startup.
- It recreates a missing venv (e.g. after `just clean`) with `uv sync`.
- It must be **sourced**, not executed; `./activate.sh` prints a hint and
  exits.
- It works from any directory, and across projects: each project's
  `activate.sh` uses that project's `just`.
- Bash only. Completion lasts only for the current shell.
- It exports `JUST_COMPLETION_REGISTERED=1`. If the venv is active without
  it (e.g. activated with `source .venv/bin/activate`), plain `just` prints
  a hint to source `activate.sh`.

To activate automatically in every terminal, add to `~/.bashrc`:

```bash
[ -f ~/path/to/project/activate.sh ] && source ~/path/to/project/activate.sh
```

`uv run just <TAB>` completes uv's arguments, not just's.

---

## Validating the setup

1. **Checks pass:** `just check`.
2. **Checks catch errors.** Break things on purpose, then revert:

   | Introduce | Expect failure from |
   |---|---|
   | Unused `import os` | `just lint` (Ruff F401) |
   | `x: int = "a"` | `just typecheck` |
   | Function missing from `_core.pyi` | `just typecheck` |
   | `let unused = 5;` in Rust | `just lint` (clippy) |
   | `assert False` in a test | `just test` |

3. **Clean rebuild:**

   ```bash
   deactivate
   uv run just clean
   uv run just check && uv run just build
   ```

4. **Fresh clone.** This proves everything needed is committed:

   ```bash
   cd /tmp && rm -rf fresh && git clone <repo> fresh && cd fresh
   uv run just check
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
| `just <TAB>` does nothing, or only completes file names | Completion not registered in this shell (`just` prints a hint) | `source ./activate.sh`; verify with `complete -p just` |
| `ModuleNotFoundError: python_native` | Not using the venv's Python | `uv run python ...` or `source ./activate.sh` |
| Rust change not visible | Ran `python` in the activated venv, which doesn't rebuild | `uv run python ...` or `uv sync` |
| Prompt shows the venv but commands fail | `.venv` deleted (e.g. `just clean`) while active | `deactivate`, then `source ./activate.sh` |
