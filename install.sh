#!/usr/bin/env bash
# Links the dotfiles into place, then installs Neovim and its tools.
# Safe to re-run. Pass --no-nvim to only link the dotfiles.
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

# Symlink so edits made on either side (and nvim's lazy-lock.json updates) land in the repo.
# A real file already at the destination is moved aside rather than overwritten.
link() {
  local src="$DOTFILES/$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    local backup="$dest.bak.$(date +%Y%m%d-%H%M%S)"
    mv "$dest" "$backup"
    echo "  backed up $dest -> $backup"
  fi
  ln -sfn "$src" "$dest"
  echo "  $dest -> $src"
}

echo "==> Linking dotfiles"
link gitconfig    ~/.gitconfig
link vimrc        ~/.vimrc
link ideavimrc    ~/.ideavimrc
link bash_aliases ~/.bash_aliases
link tmux.conf    ~/.tmux.conf
link nvim         ~/.config/nvim

# Untracked, per-machine git settings (name, email...), included by gitconfig
if [ ! -e ~/.gitconfig.local ]; then
  printf '[user]\n    name =\n    email =\n' > ~/.gitconfig.local
  echo "  created ~/.gitconfig.local: fill in your name and email"
fi

if [ "${1:-}" != "--no-nvim" ]; then
  "$DOTFILES/install-nvim.sh"
fi

echo
echo "Done. Open a new shell (or: source ~/.bashrc) and restart tmux (tmux kill-server)."
