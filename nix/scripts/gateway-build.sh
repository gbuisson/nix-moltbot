#!/bin/sh
set -e

if [ -z "${GATEWAY_PREBUILD_SH:-}" ]; then
  echo "GATEWAY_PREBUILD_SH is not set" >&2
  exit 1
fi
. "$GATEWAY_PREBUILD_SH"
if [ -z "${STDENV_SETUP:-}" ]; then
  echo "STDENV_SETUP is not set" >&2
  exit 1
fi
if [ ! -f "$STDENV_SETUP" ]; then
  echo "STDENV_SETUP not found: $STDENV_SETUP" >&2
  exit 1
fi

store_path_file="${PNPM_STORE_PATH_FILE:-.pnpm-store-path}"
if [ ! -f "$store_path_file" ]; then
  echo "pnpm store path file missing: $store_path_file" >&2
  exit 1
fi
store_path="$(cat "$store_path_file")"
export PNPM_STORE_DIR="$store_path"
export PNPM_STORE_PATH="$store_path"
export NPM_CONFIG_STORE_DIR="$store_path"
export NPM_CONFIG_STORE_PATH="$store_path"
export HOME="$(mktemp -d)"

pnpm install --offline --frozen-lockfile --ignore-scripts --store-dir "$store_path"
chmod -R u+w node_modules
rm -rf node_modules/.pnpm/sharp@*/node_modules/sharp/src/build
pnpm rebuild
bash -e -c ". \"$STDENV_SETUP\"; patchShebangs node_modules/.bin"
pnpm build
pnpm ui:build

# Copy matrix extension dependencies before pruning removes them
# The matrix extension is a workspace package but not a root prod dependency,
# so pnpm prune --prod will remove its dependencies
if [ -d extensions/matrix ]; then
  echo "Preserving matrix extension dependencies..."
  mkdir -p .matrix-deps

  # pnpm stores packages in node_modules/.pnpm/@scope+name@version/node_modules/
  # The virtual store includes all transitive dependencies for that package

  # Copy the entire virtual store node_modules for packages with complex dep trees
  # This ensures all transitive dependencies (like morgan for matrix-bot-sdk) are included
  for pkg_pattern in "@vector-im+matrix-bot-sdk@*" "@matrix-org+matrix-sdk-crypto-nodejs@*"; do
    pnpm_dir=$(find node_modules/.pnpm -maxdepth 1 -type d -name "$pkg_pattern" 2>/dev/null | head -1)
    if [ -n "$pnpm_dir" ] && [ -d "$pnpm_dir/node_modules" ]; then
      echo "Copying full dependency tree from $pnpm_dir"
      cp -rL "$pnpm_dir/node_modules/"* .matrix-deps/ 2>/dev/null || true
    fi
  done

  # Also copy simpler dependencies that may be at top level or in .pnpm
  for dep in "markdown-it" "music-metadata" "zod"; do
    if [ -d "node_modules/$dep" ] || [ -L "node_modules/$dep" ]; then
      echo "Found $dep at top level"
      cp -rL "node_modules/$dep" ".matrix-deps/$dep" 2>/dev/null || true
    else
      pnpm_dir=$(find node_modules/.pnpm -maxdepth 1 -type d -name "${dep}@*" 2>/dev/null | head -1)
      if [ -n "$pnpm_dir" ]; then
        echo "Found $dep in .pnpm"
        cp -rL "$pnpm_dir/node_modules/$dep" ".matrix-deps/$dep" 2>/dev/null || true
      fi
    fi
  done
fi

CI=true pnpm prune --prod
rm -rf node_modules/.pnpm/node_modules

# Restore matrix extension dependencies after prune
if [ -d .matrix-deps ] && [ -d extensions/matrix ]; then
  echo "Restoring matrix extension dependencies..."
  mkdir -p extensions/matrix/node_modules
  cp -r .matrix-deps/* extensions/matrix/node_modules/ 2>/dev/null || true
  rm -rf .matrix-deps
fi
