# bash completion for trash(1).
#
# Install as /usr/share/bash-completion/completions/trash or source it from
# ~/.bashrc.

_trash() {
    local cur
    cur="${COMP_WORDS[COMP_CWORD]}"
    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W '--force --dir --verbose --help --version -f -r -R -d -v --' -- "$cur") )
        return 0
    fi
    COMPREPLY=( $(compgen -f -- "$cur") )
    return 0
}

complete -o filenames -F _trash trash
