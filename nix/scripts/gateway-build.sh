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

  # pnpm stores packages in node_modules/.pnpm/@scope+name@version/node_modules/@scope/name
  # We need to find and copy from there since they're not symlinked at top level

  # Function to copy a dependency, checking both top-level and .pnpm locations
  copy_dep() {
    dep="$1"
    dep_dir="node_modules/$dep"

    if [ -d "$dep_dir" ] || [ -L "$dep_dir" ]; then
      # Found at top level
      echo "Found $dep at top level"
    else
      # Search in .pnpm - convert @scope/name to @scope+name pattern
      pnpm_pattern=$(echo "$dep" | sed 's|/|+|g')
      pnpm_dir=$(find node_modules/.pnpm -maxdepth 1 -type d -name "${pnpm_pattern}@*" 2>/dev/null | head -1)
      if [ -n "$pnpm_dir" ]; then
        dep_dir="$pnpm_dir/node_modules/$dep"
        echo "Found $dep in .pnpm at $dep_dir"
      else
        echo "NOT found: $dep"
        return 1
      fi
    fi

    # Create scope directory for scoped packages
    case "$dep" in
      @*/*)
        scope_dir=$(dirname "$dep")
        mkdir -p ".matrix-deps/$scope_dir"
        ;;
    esac

    # Copy the package
    cp -rL "$dep_dir" ".matrix-deps/$dep" 2>/dev/null
  }

  for dep in "@vector-im/matrix-bot-sdk" "@matrix-org/matrix-sdk-crypto-nodejs" "markdown-it" "music-metadata" "zod"; do
    copy_dep "$dep" || true
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
