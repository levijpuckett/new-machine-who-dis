#!/usr/bin/env bash
# Installs Neovim and the tools the config needs, then the plugins.
# Safe to re-run: it upgrades in place.
#
# Neovim version: latest stable by default. Pin one with e.g.
#   NVIM_VERSION=v0.12.1 ./install-nvim.sh
set -euo pipefail

NVIM_VERSION="${NVIM_VERSION:-latest}"
NVIM_PREFIX=/opt/nvim-linux-x86_64
BIN="$HOME/.local/bin"
mkdir -p "$BIN"

echo "==> apt packages"
sudo apt-get update
sudo apt-get install -y git curl unzip ripgrep build-essential python3-venv

echo "==> Neovim ($NVIM_VERSION)"
if [ "$NVIM_VERSION" = latest ]; then
  url=https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
else
  url=https://github.com/neovim/neovim/releases/download/$NVIM_VERSION/nvim-linux-x86_64.tar.gz
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$url" | tar -xz -C "$tmp"
sudo rm -rf "$NVIM_PREFIX"
sudo mv "$tmp/nvim-linux-x86_64" "$NVIM_PREFIX"
sudo ln -sf "$NVIM_PREFIX/bin/nvim" /usr/local/bin/nvim
nvim --version | head -1

echo "==> fzf (latest release; Ubuntu's is too old for fzf-lua's ,, picker)"
fzf_tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/junegunn/fzf/releases/latest | sed 's#.*/tag/##')
curl -fsSL "https://github.com/junegunn/fzf/releases/download/$fzf_tag/fzf-${fzf_tag#v}-linux_amd64.tar.gz" \
  | tar -xz -C "$BIN"
"$BIN/fzf" --version

echo "==> tree-sitter CLI"
curl -fsSL https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-linux-x64.gz \
  | gunzip > "$BIN/tree-sitter"
chmod +x "$BIN/tree-sitter"
"$BIN/tree-sitter" --version

# Needs ~/.config/nvim in place, so run this after your dotfiles are linked.
echo "==> Plugins (at the versions pinned in lazy-lock.json)"
PATH="$BIN:$PATH" nvim --headless "+Lazy! restore" +qa

echo "Done. The first launch of nvim finishes installing language servers and parsers."
