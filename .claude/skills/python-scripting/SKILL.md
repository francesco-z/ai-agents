---
name: python-scripting
description: Conventions and troubleshooting for writing Python scripts and tools — virtualenv isolation, dependency resolution (pip/uv), import/path errors, interpreter version issues, and packaging. Use when writing or debugging Python (.py, pyproject.toml, requirements.txt).
when_to_use: python import errors, pip/uv install conflicts, venv issues, interpreter version mismatch, ModuleNotFoundError, packaging/pyproject problems, writing Python scripts
allowed-tools: Bash(python3 *) Bash(python *) Bash(pip *) Bash(pip3 *) Bash(uv *) Bash(pytest *)
---

# Python scripting & troubleshooting

## Isolate the environment first
- `python3 --version` vs the project's required version (`pyproject.toml` `requires-python`, `.python-version`).
- Always work inside a venv: `python3 -m venv .venv && . .venv/bin/activate` (or `uv venv`). Most "works on my machine" bugs are environment leakage.

## Signature → cause → fix
- **`ModuleNotFoundError`** → not installed in the *active* env, wrong interpreter, or a `PYTHONPATH`/relative-import issue. Confirm with `python3 -c "import sys; print(sys.executable)"`.
- **`pip` dependency resolver conflict** → incompatible pins. Inspect with `pip install --dry-run` / `uv pip compile`; resolve versions deliberately rather than `--ignore-installed`.
- **Import works as module but not as script (or vice-versa)** → package vs script execution; use `python -m package.module` and proper `__init__.py`/`src` layout.
- **C-extension build failure** (e.g. `error: command 'gcc' failed`) → missing system build deps or headers; prefer wheels, check the package's build requirements.
- **Wrong interpreter picked** → shebang, `PATH`, or activated venv. Pin the interpreter explicitly.

## Writing scripts (defaults)
- Add type hints; run `ruff`/`flake8` and `mypy` if configured.
- Use `argparse`/`click` for CLIs, `pathlib` over string paths, and `logging` over `print` for tools.
- Tests with `pytest`; keep fixtures isolated. Never hardcode secrets — read from env.
- Pin runtime deps in `requirements.txt`/`pyproject.toml`; commit the lock (`uv.lock`/`requirements.txt`).
