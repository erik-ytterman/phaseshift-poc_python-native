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
changed. See [From clone to runnable project](#from-clone-to-runnable-project)
for what happens.

| Recipe | What it does |
|---|---|
| `just fmt` | Format Python (Ruff) and Rust (`cargo fmt`) |
| `just lint` | Ruff, format checks, `cargo clippy -D warnings` |
| `just typecheck` | mypy (strict) |
| `just test` | `cargo test` + `pytest` |
| `just check` | `lint` + `typecheck` + `test` |
| `just profile <script> [args]` | py-spy flame graph incl. Rust frames → `profile.svg` |
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

The name must be lowercase letters, digits and single hyphens (e.g.
`my-pkg`); the import name replaces hyphens with underscores (`my_pkg`).

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
    fn factor(py: Python<'_>, n: u64) -> Vec<u64> {
        py.detach(|| super::factor_impl(n))
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

### From clone to runnable project

One command takes a fresh clone to a working package:

```bash
uv sync          # or any `uv run ...`, e.g. `uv run just check`
```

That runs these steps:

1. **Python.** uv reads `.python-version` (3.13) and uses a matching
   interpreter, downloading one into `~/.local/share/uv/python` if none is
   installed.
2. **Venv.** uv creates `.venv/` in the project.
3. **Dependencies.** uv installs the exact versions from `uv.lock` into
   `.venv`, including the `dev` group (maturin, ruff, mypy, pytest, py-spy,
   just). This comes first because of `no-build-isolation-package`: the
   project is built with the venv's own maturin.
4. **Build.** `[build-system]` in `pyproject.toml` names maturin as the
   build backend, so uv asks it for an **editable** build (PEP 660).
   maturin then:
   - runs `cargo build --release` on `src/lib.rs`, using the pyo3 features
     from `Cargo.toml` (`abi3-py313`: one binary for every Python ≥ 3.13)
   - copies the result to `src/python_native/_core.abi3.so`, next to the
     Python code (`.pyd` on Windows)
   - writes a wheel to `target/wheels/` that contains only a pointer file,
     `python_native.pth`, holding the path to `src/`
5. **Install.** uv installs that wheel, which puts the `.pth` file into
   `.venv/lib/python3.13/site-packages/`.
6. **Run.** At startup the venv's Python adds `src/` to `sys.path` because
   of the `.pth` file. `import python_native` loads
   `src/python_native/__init__.py`, which imports `_core`, which loads the
   `.so`.

Rust dependencies are compiled once, into `target/release/`. After that,
every `uv run` compares the files listed in `[tool.uv] cache-keys` (the
`.rs` files, `Cargo.toml`, `Cargo.lock`, `pyproject.toml`) with the last
build, and repeats steps 4–5 only if one changed. Then only this crate is
recompiled.

### Editable install

Because the venv points at `src/` instead of holding a copy, edits show up
without reinstalling. That is also how `examples/` and `tests/` find the
package: through the venv, not their location on disk.

| You edit | Takes effect |
|---|---|
| `.py` files | Immediately (read from `src/`) |
| `.pyi` stubs | Next mypy run |
| `.rs` files | Next `uv run` or `uv sync` (rebuilds on change) |

It only works with the venv's Python: a system `python3` gives
`ModuleNotFoundError`.

### Building a wheel for distribution

`just build` (`maturin build --release`) builds a regular wheel into
`target/wheels/`, e.g.
`python_native-0.1.0-cp313-abi3-manylinux_2_34_x86_64.whl`. Unlike the
editable wheel, it contains the package itself (`__init__.py`,
`_core.abi3.so`, `_core.pyi`, `py.typed`), with no link back to your source.
It doesn't touch `.venv`.

Install it in any environment with Python ≥ 3.13 on the same platform
(here Linux x86_64, glibc ≥ 2.34). No Rust toolchain is needed there:

```bash
uv pip install target/wheels/python_native-*.whl   # or: pip install ...
```

| Command | Compiles Rust | Installs into `.venv` | Output |
|---|---|---|---|
| `uv sync` / `uv run` | If changed | Yes, editable | `.so` in `src/` + `.pth` |
| `just build` | Yes | **No** | Self-contained wheel in `target/wheels/` |

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
  (strict, covering `src/python_native`, `tests` and `examples`) and
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
  uv run python examples/do_factorize.py 10000000000000061   # a 17-digit prime, ~0.5 s
  ```

  `cargo test` and `cargo clippy` use the debug profile; that only affects
  Rust-side tests.
- **Crossing the boundary costs.** Converting a large Python list to a
  `Vec` copies every element. Rust pays off when it does real work per item,
  or with NumPy arrays via `rust-numpy` (zero-copy).
- Release the GIL during long Rust computations with `py.detach(...)`
  (named `allow_threads` before PyO3 0.26), as `factor` does. Taking a
  `py: Python<'_>` argument gives access to it; Python callers don't see
  that argument. The closure can't touch Python objects.
- On macOS, `py-spy` needs `sudo`.

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| `just <TAB>` does nothing, or only completes file names | Completion not registered in this shell (`just` prints a hint) | `source ./activate.sh`; verify with `complete -p just` |
| `ModuleNotFoundError: python_native` | Not using the venv's Python | `uv run python ...` or `source ./activate.sh` |
| Rust change not visible | Ran `python` in the activated venv, which doesn't rebuild | `uv run python ...` or `uv sync` |
| Prompt shows the venv but commands fail | `.venv` deleted (e.g. `just clean`) while active | `deactivate`, then `source ./activate.sh` |
