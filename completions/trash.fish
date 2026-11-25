# fish completion for trash(1).
#
# Install as ~/.config/fish/completions/trash.fish.

complete -c trash -s f -l force -d 'Ignore missing targets'
complete -c trash -s r -s R -d 'Trash a directory and its contents'
complete -c trash -s d -l dir -d 'Trash an empty directory without -r'
complete -c trash -s v -l verbose -d 'Print what was moved'
complete -c trash -l help -d 'Print the help and exit'
complete -c trash -l version -d 'Print the version and exit'
