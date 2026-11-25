#compdef trash
#
# Install as a file named `_trash` in a directory of your $fpath.

_arguments -s \
  '(-f --force)'{-f,--force}'[ignore missing targets]' \
  '(-r -R)'{-r,-R}'[trash a directory and its contents]' \
  '(-d --dir)'{-d,--dir}'[trash an empty directory without -r]' \
  '(-v --verbose)'{-v,--verbose}'[print what was moved]' \
  '--help[print the help and exit]' \
  '--version[print the version and exit]' \
  '--[end of options]' \
  '*:file:_files'
