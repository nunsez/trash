# trash

`trash` moves files and directories to the system trash instead of deleting
them. It is an replacement for `rm` on Linux, macOS and Windows, written in
[V](https://vlang.io), and it also works as a V library.

Nothing is ever deleted permanently. A target that cannot be moved to the
trash - a volume without one, an object larger than the Windows Recycle
Bin - is reported as an error and left exactly where it was.

```sh
trash notes.txt           # goes to the trash
trash -r old-project/     # directories need -r, like rm
trash -v build.log        # prints "trashed 'build.log'"
```

## Platforms

| Platform | Where it goes | Notes |
| -------- | ------------- | ----- |
| Linux | `$XDG_DATA_HOME/Trash` (freedesktop.org Trash specification), else `$topdir/.Trash/$uid`, else `$topdir/.Trash-$uid` | Compatible with `gio trash`, `trash-cli`, Nautilus and Dolphin |
| macOS | `~/.Trash` on the boot volume, `/.Trashes/<uid>` on other volumes | Uses `NSFileManager`, so Finder's "Put Back" works |
| Windows | the Recycle Bin | Uses `IFileOperation` with `FOF_ALLOWUNDO` |

## Install

Requires V 0.5.2 or newer.

```sh
git clone https://github.com/nunsez/trash
cd trash
./make.vsh install      # release build, then installs into /usr/local
```

`install` honours `PREFIX` and `DESTDIR`:

```sh
PREFIX=$HOME/.local ./make.vsh install
DESTDIR=/tmp/pkg PREFIX=/usr ./make.vsh install
PREFIX=$HOME/.local ./make.vsh uninstall
```

`uninstall` removes exactly the five files `install` wrote, never a directory,
and reports a file that is not there instead of failing, so it is safe to run
twice.

To use it as a library, add the repository to your `~/.vmodules` and
`import trash`:

```v
import trash

results := trash.put(['notes.txt'])
for result in results {
	if result.reason != '' {
		eprintln('${result.path}: ${result.reason}')
	}
}

// Options are optional named arguments:
// trash.put(['old-project'], recursive: true)
```

## Usage

```
Usage: trash [OPTION]... FILE...
Move each FILE into the system trash instead of deleting it.

  -f, --force     ignore missing targets; never changes the exit status
  -r, -R          trash a directory and its contents
  -d, --dir       trash an empty directory without -r
  -v, --verbose   print "trashed 'FILE'" for every target that was moved
      --help      print this help and exit
      --version   print the version and exit
      --          end of options
```

Exit status is `0` when every target was trashed and `1` when any of them
failed. Failures are reported per item and the remaining targets are still
processed, like `rm`.

### Using it as `rm`

`trash` accepts the flags of `rm` that have a meaning without permanent
deletion: `-f`, `-r`, `-R`, `-d`, `-v`. Everything else is **rejected, not
ignored**, so a script cannot silently lose its safety net:

```sh
trash -i file       # trash: invalid option -- 'i'
trash --recursive d # trash: unrecognized option '--recursive'
```

That is deliberate: `-i`, `-I`, `--interactive`, `--preserve-root` and friends
exist to control a destructive operation that `trash` does not have. If you
alias `rm` to `trash`, pass `-r`/`-f` explicitly in scripts and drop the
interactive flags.

## Differences from `rm`

`trash` follows `rm` wherever both can be safe. Where they differ, it is because
`rm` would destroy something:

- **Directories need `-r`.** A directory is refused with `Is a directory` unless
  `-r`/`-R` (or `-d` for an empty one) is given.
- **Only the last component is never followed.** A symlink in the middle of a
  path is resolved exactly like `rm` resolves it, so `trash /tmp/x` works where
  `/tmp` is a symlink. A symlink given as the target itself is trashed as a
  link, never dereferenced.
- **Mount points are refused**, and so are directories that contain one, because
  trashing them would move an entire filesystem.
- **The trash directory and its ancestors are refused.**
- **`.` and `..` as the last component are refused**, and so is the current
  directory.
- **A missing target is an error** (status `1`) unless `-f` is given, exactly as
  with `rm`.
- **Windows:** paths over 259 characters, reserved device names (`CON`, `NUL`,
  `COM1`...), a `:` after the drive, a trailing dot or space, and UNC paths are
  refused instead of being deleted permanently.
- **Windows:** an object that does not fit into the Recycle Bin is refused.

## Development

```sh
./make.vsh            # fast development build, bin/trash-dev (default)
./make.vsh ci         # the gate: fmt, vet, test, release build
./make.vsh test       # one flow only
./make.vsh --help     # every flow and flag
./make.vsh install    # release build, then binary, man page and completions
./make.vsh uninstall  # remove what install put into PREFIX
```

Tests use a temporary directory and a temporary `XDG_DATA_HOME`; they never
write into the real trash. On macOS the success paths are checked by hand,
because `NSFileManager` chooses the destination itself and macOS does not let a
test read `~/.Trash`.
