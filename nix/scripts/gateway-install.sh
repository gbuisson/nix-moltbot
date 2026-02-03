#!/bin/sh
set -e
mkdir -p "$out/lib/openclaw" "$out/bin"

cp -r dist node_modules package.json ui "$out/lib/openclaw/"
if [ -d extensions ]; then
  cp -r extensions "$out/lib/openclaw/"
fi

if [ -d docs/reference/templates ]; then
  mkdir -p "$out/lib/openclaw/docs/reference"
  cp -r docs/reference/templates "$out/lib/openclaw/docs/reference/"
fi

if [ -z "${STDENV_SETUP:-}" ]; then
  echo "STDENV_SETUP is not set" >&2
  exit 1
fi
if [ ! -f "$STDENV_SETUP" ]; then
  echo "STDENV_SETUP not found: $STDENV_SETUP" >&2
  exit 1
fi

bash -e -c '. "$STDENV_SETUP"; patchShebangs "$out/lib/openclaw/node_modules/.bin"'
if [ -d "$out/lib/openclaw/ui/node_modules/.bin" ]; then
  bash -e -c '. "$STDENV_SETUP"; patchShebangs "$out/lib/openclaw/ui/node_modules/.bin"'
fi

# Work around missing dependency declaration in pi-coding-agent (strip-ansi).
# Ensure it is resolvable at runtime without changing upstream.
pi_pkg="$(find "$out/lib/openclaw/node_modules/.pnpm" -path "*/node_modules/@mariozechner/pi-coding-agent" -print | head -n 1)"
strip_ansi_src="$(find "$out/lib/openclaw/node_modules/.pnpm" -path "*/node_modules/strip-ansi" -print | head -n 1)"

if [ -n "$strip_ansi_src" ]; then
  if [ -n "$pi_pkg" ] && [ ! -e "$pi_pkg/node_modules/strip-ansi" ]; then
    mkdir -p "$pi_pkg/node_modules"
    ln -s "$strip_ansi_src" "$pi_pkg/node_modules/strip-ansi"
  fi

  if [ ! -e "$out/lib/openclaw/node_modules/strip-ansi" ]; then
    mkdir -p "$out/lib/openclaw/node_modules"
    ln -s "$strip_ansi_src" "$out/lib/openclaw/node_modules/strip-ansi"
  fi
fi

if [ -n "${PATCH_CLIPBOARD_SH:-}" ]; then
  "$PATCH_CLIPBOARD_SH" "$out/lib/openclaw" "$PATCH_CLIPBOARD_WRAPPER"
fi

# Work around missing combined-stream dependency for form-data in pnpm layout.
combined_stream_src="$(find "$out/lib/openclaw/node_modules/.pnpm" -path "*/combined-stream@*/node_modules/combined-stream" -print | head -n 1)"
form_data_pkgs="$(find "$out/lib/openclaw/node_modules/.pnpm" -path "*/node_modules/form-data" -print)"
if [ -n "$combined_stream_src" ]; then
  if [ ! -e "$out/lib/openclaw/node_modules/combined-stream" ]; then
    ln -s "$combined_stream_src" "$out/lib/openclaw/node_modules/combined-stream"
  fi
  if [ -n "$form_data_pkgs" ]; then
    for pkg in $form_data_pkgs; do
      if [ ! -e "$pkg/node_modules/combined-stream" ]; then
        mkdir -p "$pkg/node_modules"
        ln -s "$combined_stream_src" "$pkg/node_modules/combined-stream"
      fi
    done
  fi
fi

# Work around missing hasown dependency for form-data in pnpm layout.
hasown_src="$(find "$out/lib/openclaw/node_modules/.pnpm" -path "*/hasown@*/node_modules/hasown" -print | head -n 1)"
if [ -n "$hasown_src" ]; then
  if [ ! -e "$out/lib/openclaw/node_modules/hasown" ]; then
    ln -s "$hasown_src" "$out/lib/openclaw/node_modules/hasown"
  fi
  if [ -n "$form_data_pkgs" ]; then
    for pkg in $form_data_pkgs; do
      if [ ! -e "$pkg/node_modules/hasown" ]; then
        mkdir -p "$pkg/node_modules"
        ln -s "$hasown_src" "$pkg/node_modules/hasown"
      fi
    done
  fi
fi

# === MATRIX EXTENSION SUPPORT ===
# Link matrix extension dependencies to node_modules
matrix_ext="$out/lib/openclaw/extensions/matrix"
if [ -d "$matrix_ext" ]; then
  mkdir -p "$matrix_ext/node_modules/@vector-im" "$matrix_ext/node_modules/@matrix-org"
  
  # Link matrix-bot-sdk (pnpm uses + instead of / in folder names)
  matrix_bot_sdk_src="$(find "$out/lib/openclaw/node_modules/.pnpm" -type d -name "matrix-bot-sdk" | grep "@vector-im" | head -n 1)"
  if [ -n "$matrix_bot_sdk_src" ]; then
    echo "Linking matrix-bot-sdk from: $matrix_bot_sdk_src"
    ln -sfn "$matrix_bot_sdk_src" "$matrix_ext/node_modules/@vector-im/matrix-bot-sdk"
    mkdir -p "$out/lib/openclaw/node_modules/@vector-im"
    ln -sfn "$matrix_bot_sdk_src" "$out/lib/openclaw/node_modules/@vector-im/matrix-bot-sdk"
  else
    echo "WARNING: matrix-bot-sdk not found in node_modules/.pnpm"
  fi
  
  # Link matrix-sdk-crypto-nodejs
  matrix_crypto_src="$(find "$out/lib/openclaw/node_modules/.pnpm" -type d -name "matrix-sdk-crypto-nodejs" | grep "@matrix-org" | head -n 1)"
  if [ -n "$matrix_crypto_src" ]; then
    echo "Linking matrix-sdk-crypto-nodejs from: $matrix_crypto_src"
    ln -sfn "$matrix_crypto_src" "$matrix_ext/node_modules/@matrix-org/matrix-sdk-crypto-nodejs"
    mkdir -p "$out/lib/openclaw/node_modules/@matrix-org"
    ln -sfn "$matrix_crypto_src" "$out/lib/openclaw/node_modules/@matrix-org/matrix-sdk-crypto-nodejs"
  else
    echo "WARNING: matrix-sdk-crypto-nodejs not found in node_modules/.pnpm"
  fi
  
  # Link music-metadata (for audio file handling)
  music_metadata_src="$(find "$out/lib/openclaw/node_modules/.pnpm" -type d -name "music-metadata" | head -n 1)"
  if [ -n "$music_metadata_src" ]; then
    echo "Linking music-metadata from: $music_metadata_src"
    ln -sfn "$music_metadata_src" "$matrix_ext/node_modules/music-metadata"
    ln -sfn "$music_metadata_src" "$out/lib/openclaw/node_modules/music-metadata"
  else
    echo "WARNING: music-metadata not found in node_modules/.pnpm"
  fi
fi
# === END MATRIX EXTENSION SUPPORT ===

bash -e -c '. "$STDENV_SETUP"; makeWrapper "$NODE_BIN" "$out/bin/openclaw" --add-flags "$out/lib/openclaw/dist/index.js" --set-default OPENCLAW_NIX_MODE "1" --set-default MOLTBOT_NIX_MODE "1" --set-default CLAWDBOT_NIX_MODE "1"'
ln -s "$out/bin/openclaw" "$out/bin/moltbot"
