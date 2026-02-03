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

# NOTE: Skipping pnpm prune --prod to preserve matrix extension dependencies
# The matrix extension needs its full transitive dependency tree (express, morgan, etc.)
# which would be removed by pruning since it's not a direct root dependency.
# Trade-off: ~50MB larger package but fully working matrix channel support.
rm -rf node_modules/.pnpm/node_modules

# Copy matrix crypto native binary if available
# The @matrix-org/matrix-sdk-crypto-nodejs package downloads this via postinstall,
# which is skipped in nix build, so we pre-fetch and copy it manually
if [ -n "${MATRIX_CRYPTO_LIB_SRC:-}" ] && [ -n "${MATRIX_CRYPTO_LIB_NAME:-}" ]; then
  crypto_dir="node_modules/.pnpm/@matrix-org+matrix-sdk-crypto-nodejs@0.4.0/node_modules/@matrix-org/matrix-sdk-crypto-nodejs"
  if [ -d "$crypto_dir" ]; then
    echo "Installing matrix crypto native binary: $MATRIX_CRYPTO_LIB_NAME"
    cp "$MATRIX_CRYPTO_LIB_SRC" "$crypto_dir/$MATRIX_CRYPTO_LIB_NAME"
    chmod 755 "$crypto_dir/$MATRIX_CRYPTO_LIB_NAME"
  fi
fi
