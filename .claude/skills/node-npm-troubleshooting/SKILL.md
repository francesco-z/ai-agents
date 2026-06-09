---
name: node-npm-troubleshooting
description: Diagnose and fix Node.js / npm build and dependency problems — install failures, lockfile drift, peer-dependency conflicts, version mismatches, ESM/CJS errors, native module (node-gyp) build failures, and broken scripts. Use for Node/TypeScript projects.
when_to_use: npm/yarn/pnpm install errors, ERESOLVE peer deps, module not found, ESM vs CommonJS, node-gyp build failure, engine/version mismatch, failing build scripts
allowed-tools: Bash(node *) Bash(npm *) Bash(npx *) Bash(yarn *) Bash(pnpm *)
---

# Node / npm troubleshooting

## Establish the environment first
- `node --version` vs `.nvmrc` and `package.json` `engines`. Version drift is the #1 hidden cause.
- Which package manager? Presence of `package-lock.json` / `yarn.lock` / `pnpm-lock.yaml` decides — don't mix them.

## Signature → cause → fix
- **`ERESOLVE could not resolve` (peer deps)** → incompatible peer-dependency tree. Prefer aligning versions; use `--legacy-peer-deps` only as a documented, temporary workaround, never silently.
- **Lockfile drift / CI install fails but local works** → `package.json` and lockfile disagree. Reproduce with a clean install: `rm -rf node_modules && npm ci`. Fix by regenerating and committing the lockfile.
- **`Cannot find module` / `ERR_MODULE_NOT_FOUND`** → ESM/CJS mismatch (`"type": "module"`, `.mjs/.cjs`, `import` vs `require`), missing dep, or path/case issue. Check `package.json` `type`, `exports`, and `tsconfig` `module`/`moduleResolution`.
- **`node-gyp` / native build failure** → missing toolchain (python, make, C/C++) or Node ABI mismatch. Check prebuilt binaries, Node version, and `node-gyp` requirements; avoid forcing a rebuild blindly.
- **Script fails (`npm run build`)** → run with more output, isolate the failing step, check env vars and that `devDependencies` are installed (CI `NODE_ENV=production` skips them).

## Controlled experiments
A clean reinstall (`rm -rf node_modules && <pm> ci|install`) is a diagnostic, not a cure — note what it changed. Keep fixes minimal and commit lockfile changes deliberately.
