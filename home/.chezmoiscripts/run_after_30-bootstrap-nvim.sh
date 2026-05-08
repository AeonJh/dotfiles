#!/usr/bin/env bash

set -euo pipefail

NVIM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/chezmoi"
MARKER="$STATE_DIR/nvim-plugins-bootstrapped"

if [[ -f "$MARKER" ]]; then
  echo "[chezmoi] Neovim plugins already bootstrapped, skip"
  exit 0
fi

if ! command -v nvim >/dev/null 2>&1; then
  echo "[chezmoi] nvim not found, skip Neovim plugin bootstrap"
  exit 0
fi

if [[ ! -d "$NVIM_CONFIG" ]]; then
  echo "[chezmoi] $NVIM_CONFIG not found, skip Neovim plugin bootstrap"
  exit 0
fi

if [[ ! -f "$NVIM_CONFIG/init.lua" && ! -f "$NVIM_CONFIG/init.vim" ]]; then
  echo "[chezmoi] no init.lua/init.vim found in $NVIM_CONFIG, skip Neovim plugin bootstrap"
  exit 0
fi

mkdir -p "$STATE_DIR"

echo "[chezmoi] bootstrapping AstroNvim/Neovim plugins..."

if command -v timeout >/dev/null 2>&1; then
  timeout 600s nvim --headless +q
else
  nvim --headless +q
fi

touch "$MARKER"
echo "[chezmoi] Neovim plugins bootstrapped"
