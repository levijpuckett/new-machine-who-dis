# Case-insensitive autocomplete
bind "set completion-ignore-case on"

# Shortcut to grep history
alias gh='history | grep'

alias less='less -NF --use-color'

# "find" alias to search for file by substring.
fs() {
    # If no arguments are given, print usage instructions
    if [ -z "$1" ]; then
        echo "Usage: fsub [directory] <substring>"
        return 1
    fi

    # If 2 arguments are given: $1 is directory, $2 is substring
    # If 1 argument is given: default to current directory (.), $1 is substring
    if [ -n "$2" ]; then
        local dir="$1"
        local sub="$2"
    else
        local dir="."
        local sub="$1"
    fi

    find "$dir" -type f -iname "*$sub*"
}

