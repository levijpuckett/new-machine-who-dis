# Locally installed tools (fzf, tree-sitter, ...) take priority over apt's
export PATH="$HOME/.local/bin:$PATH"

# Neovim everywhere as EDITOR, VISUAL, and "vim"
export EDITOR=nvim
export VISUAL=nvim
alias vim=nvim

# Case-insensitive autocomplete
bind "set completion-ignore-case on"

# Shortcut to grep history
alias gh='history | grep'

alias less='less -NF --use-color'

# fd for fd-find
alias fd=fdfind
