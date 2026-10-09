My preferred default config for a fresh dev machine.

# Dotfiles

 - gitconfig
 - vimrc
 - ideavimrc
 - tmux.conf
 - bash\_aliases


# Neo Vim

The nvim config involves installing a number of extensions for nvim, which it will do on the
first launch.


# Install

install.sh will move all the dotfiles to the home directory via symlinks, so that any
tinkering can be pushed back to this repo easily. It will also fetch and install the programs
that use these dotfiles (nvim, tmux, etc).

