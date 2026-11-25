# trash — Technical Specification

This document is the single source of truth for the project and the
implementation contract. Code that disagrees with it is wrong. Changes require
an explicit decision recorded in `§ 3 Fixed decisions` or `§ 4 Deviations from rm`.

Identifiers of the form `Dn` refer to the decisions in `§ 3`.

## Contents

1. Purpose
2. Scope
3. Fixed decisions
4. Deviations from `rm`
5. CLI contract
6. Library API
7. Architecture
8. Platform backends
9. Safety guards

---

## 1. Purpose

`trash` is a drop-in replacement for `rm` on Linux, macOS and Windows. It
accepts the same arguments as `rm` and the flag subset in `§ 5.2`, and instead
of destroying data it moves every target into the **platform's system trash**:
the freedesktop.org Trash on Linux, `~/.Trash` / `/.Trashes/<uid>` on macOS,
the Recycle Bin on Windows. It never deletes anything permanently: when an
object cannot be trashed, the run fails.

It ships two artifacts from one codebase:

- a CLI binary, meant to be aliased as `rm`;
- a V library (`module trash`) with a non-interactive API.

Consequences that shape every other decision:

- **Compatibility with foreign tools is a feature.** An item trashed by `trash`
  must be visible and restorable by `gio trash`, `trash-cli`, Nautilus, KDE
  Dolphin, Finder and Explorer. This forbids any private store or index.
- **`rm` semantics win over trash convenience.** Where the two conflict, `rm`
  behavior is preserved and the conflict is listed in `§ 4`.
- **No global state.** The library has no current-trash singleton; everything is
  passed explicitly.

## 2. Scope

### 2.1 In scope

- `put` with the supported `rm` flag subset (`D28`) on all three platforms.
- Platform backends that use only the OS-provided trash.
- Library API for the same operation, usable by other V programs.
- Safety guards (`§ 9`), typed errors, deterministic exit codes.

### 2.2 Out of scope

- Own store, own index, own metadata format (SQLite, JSON, or another custom
  format). Rejected: it breaks the system-trash guarantee and duplicates the
  platform's own metadata.
- Retention policies, quotas, background garbage collection, size reporting as a
  feature (the Windows quota *check* of `§ 8.3` is not such a feature).
- Copy-based cross-filesystem fallback: never. When a volume has no usable
  trash, the object is refused with an error (`§ 5.5`).
- Restoring Finder "Put Back" metadata by hand; macOS gets it from the system
  API or not at all.
- Listing, restoring, and emptying the trash. `put` is the whole supported
  contract.
- FreeBSD, OpenBSD, NetBSD, Solaris, Android, iOS, WASM.
- GUI, TUI, interactive modes (`-i`, `-I`, `--interactive`).
- Configuration files. Only the environment variables the platform specs define.

## 3. Fixed decisions

Identifiers are stable. Gaps in the sequence indicate decisions that are not
part of the current contract.

| #   | Question | Decision | Rationale |
| --- | -------- | -------- | --------- |
| D1  | Storage | System trash only | Interop with file managers; no state to corrupt |
| D2  | Canon for `rm` semantics | POSIX `rm` for `-f`, `-R`, `-r`; GNU `rm` for `-d`. No other flags exist (`D28`) | Small surface, POSIX is the portable contract |
| D3  | `rm` without `-r` on a directory | Error, as in `rm` | Drop-in safety |
| D4  | `-i`, `-I`, `--interactive` | Not supported | They are the only reason to walk a tree before moving it; without them a directory moves atomically as one object |
| D5  | `-v`, `--verbose` | Supported; prints `trashed 'PATH'` for every moved target | Cheap, and the only way to see what happened |
| D6  | Exit codes | `0` success, `1` any failure, including usage errors | GNU-compatible |
| D7  | Flag precedence | Not applicable: `-f` is the only modifier and there is nothing to override | — |
| D8  | Program name in messages | `trash` | — |
| D9  | Linux backend | freedesktop.org Trash specification, no extensions | Interoperability is the primary requirement |
| D10 | macOS backend | `NSFileManager -trashItemAtURL:resultingItemURL:error:` via the Objective-C runtime, single path, no fallback | Gives working Finder "Put Back" without a GUI session or AppleScript; a fallback would misreport the result |
| D11 | Windows backend | `IFileOperation` COM API (C interop) | `SHFileOperationW` is deprecated; hand-written `$Recycle.Bin` writes are unacceptable |
| D12 | C interop | Allowed where a platform API has no pure-V equivalent: macOS Foundation in `internal/darwin`, Windows COM in `internal/windows`, and the Unix syscall wrappers in `internal/fsx`/`internal/pathx` (`openat`, `fstatat`, `renameat`, `renameat2`/`renameatx_np`, `mkdirat`, `fchmod`, `pathconf`, `fcntl(F_GETPATH)`, `getmntinfo`) | vlib has no descriptor-relative calls at all, so `D30`/`D32` are impossible in pure V; no third-party V modules anywhere |
| D13 | Public API shape | `Options` structs + free functions returning per-item results; no global state | `rm` semantics = "continue after errors" |
| D17 | `list` / `restore` / `empty` | Not supported | `put` is the whole supported contract; the other operations are out of scope (`§ 2.2`) |
| D18 | Volume without a usable trash | Error `no usable trash directory on this volume`, exit `1`, nothing deleted | There is no permanent-deletion path (`D33`) |
| D19 | Object larger than the Windows Recycle Bin quota | Error, nothing deleted. The size is computed recursively on Windows for this check only | `IFileOperation` would otherwise delete it permanently without notice |
| D20 | BSD flags (`-W`, `-x`, `-P`) | Not supported: usage error | Out of the supported surface (`D28`) |
| D23 | Name collisions in the trash | Linux `.1`/`.2`; macOS and Windows left entirely to the OS | Users see what the rest of the system produces |
| D25 | Windows paths longer than the shell API limit | Error: `path too long for the Recycle Bin`, exit `1`. No permanent-delete fallback | Shell APIs do not understand `\\?\`; converting a trash operation into a permanent delete is unacceptable |
| D26 | Windows junctions (reparse points) | Never dereferenced; the reparse point itself goes to the trash. Refused only when it resolves to a volume root | Same rule as a symlink; a volume mount point cannot be moved |
| D27 | Windows reserved device names, alternate data streams (`:`), trailing dots and spaces | Unsupported: clear error, exit `1`, nothing touched | Only `\\?\` paths handle them, and the shell API rejects those |
| D28 | Supported flag set | `-f`/`--force`, `-r`/`-R`, `-d`/`--dir`, `-v`/`--verbose`, `--`, `--help`, `--version`. Everything else is a usage error. `/` protection is unconditional and has no flag | One source of truth for the CLI surface |
| D29 | A directory that contains a mount point | Refused on Linux and macOS, decided from the mount table without walking the tree. Windows needs no such check, because its mount points are reparse points (`D26`) | `rename()` would relocate the mount into the trash, and emptying the trash would then delete the volume's contents |
| D30 | Path access on Unix | The parent directory is resolved once with `realpath(3)`, then descended component by component with `openat(O_NOFOLLOW)`, guards evaluated from `fstatat`, the move is `renameat` (`§ 7.2`) | `rm` resolves symlinks in the middle of a path and users depend on it; resolving first and then refusing to follow anything gives the same result as `rm` while a component swapped after the resolution still fails the descent |
| D31 | Durability of `.trashinfo` | `fsync` the info file before the payload is moved. The `info/` directory is not fsynced | A zero-length info file after a power cut makes the item unrecoverable; a directory fsync per item is not justified by its cost |
| D32 | Overwriting an existing trash name | No-replace rename: `RENAME_NOREPLACE` on Linux, `RENAME_EXCL` on macOS; fallback is `fstatat` + `renameat` with a documented race | `rename` silently replaces the destination, which would destroy another item |
| D33 | Permanent deletion | Does not exist. An object that cannot be trashed is an error; there is no prompt, no `-f` consent, no delete path | A utility whose purpose is to prevent data loss must not include a hidden delete path |
| D34 | Backend contract | `put(Target)`; on Unix `Target` is `{dir_fd int, name string, st_dev u64, st_ino u64}`, on Windows `{abs_path string}` (`§ 7.1`) | A path parameter would force the backend to re-resolve it, reopening the race `D30` closes |
| D35 | Windows COM threading | `put` calls `CoInitializeEx(APARTMENTTHREADED)` on the calling thread and skips `CoUninitialize` when COM was already initialized there | The library promises thread safety; COM is per-thread |
| D36 | Mount-point lookup | The target's canonical path comes from the descriptor chain (`/proc/self/fd/N` on Linux, `fcntl(F_GETPATH)` on macOS) and is compared with unescaped mount table entries | The mount table is path-based, so the path must not come from `argv` |
| D37 | macOS failures | A `trashItemAtURL` failure is the error; there is no `rename` fallback | A fallback would either report success falsely or lose Finder metadata |
| D38 | Library flag surface | `PutOptions` is `{force, recursive, dir}`; the CLI only maps its flags onto it | The module owns the directory rules, so it must know the flags |
| D39 | Platform wiring | `put_linux.v`, `put_darwin.v`, `put_windows.v` at the module root select the backend and the trash candidates, and `put_nix.v` holds the shared Unix guards; V picks a plain `.v` file by its `_linux`/`_darwin`/`_windows` suffix | `import` cannot sit inside `$if`, so the platform split has to happen at file level |
| D40 | Canonical target path | The canonical path of the parent descriptor (`/proc/self/fd/N`, `fcntl(F_GETPATH)`) plus `/` plus `name` | The final component is never opened (`§ 7.2`), so its own canonical path cannot be obtained |
| D41 | Unreadable mount table | Fail closed: `cannot read the mount table`, exit `1`, nothing touched | Without the table the mount guards cannot be evaluated, and guessing is worse than refusing |
| D42 | `.` and `..` components | A final `.` or `..` component is refused with `refusing to trash '.' or '..'`; `..` in the middle is descended like any other directory component | `rm` parity; `..` cannot be a symlink, so descending it keeps `§ 7.2` intact |
| D43 | Linux home trash creation | `$XDG_DATA_HOME/Trash` is created only when `$XDG_DATA_HOME` already exists and lies on the target's volume; if `$XDG_DATA_HOME` is missing the candidate is skipped | Creating a `$HOME`-relative chain on an arbitrary volume is a surprise; the per-volume candidates exist for that case |
| D44 | `NAME_MAX` shortening | Truncate on a UTF-8 boundary, keeping the extension when it fits with at least one byte of stem (`§ 8.1` has the exact rule) | A name that does not fit would fail with `ENAMETOOLONG` and lose the item; an extension alone is not a name |
| D45 | `Path` in `.trashinfo` | Relative to `$topdir`, no leading `/` | Matches the freedesktop.org definition and is accepted by `gio` and `trash-cli` |
| D46 | Windows trash path | `PutResult.trash_path` is `''` on Windows, success or not | `IFileOperation` does not report the resulting Recycle Bin path without a COM progress sink |
| D47 | Windows quota | `MaxCapacity` from `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume\{GUID}`; when absent, the Windows default (10% below 40 GB, else 5%). Refuse when `size + used > capacity` | A conservative estimate is preferable to a permanent delete by the shell |
| D48 | Windows path rules | `:` rejected after the drive prefix, a trailing dot or space rejected on the last component only, every UNC path refused, the limit is 259 UTF-16 code units of the absolute path | `D25`–`D27` restated in the terms the implementation can check |

## 4. Deviations from rm

Every intentional difference from `rm`, with the reason. Anything not in this
table must behave like `rm`.

| Area | `rm` | `trash` | Why |
| --- | --- | --- | --- |
| Effect | data destroyed | data moved to system trash | the purpose of the tool |
| Free space | freed immediately | freed only when the trash is emptied | inherent to a trash |
| Error text | `rm: cannot remove 'x': ...` | `trash: cannot trash 'x': ...` | never claim to have destroyed data |
| `-v` output | `removed 'x'` | `trashed 'x'` | same reason |
| Unsupported `rm` flags (`-i`, `-I`, `--interactive`, `--recursive`, `--one-file-system`, `--preserve-root`, `--preserve-root=all`, `--no-preserve-root`, `-x`, `-P`, `-W`) | accepted by `rm` | `trash: invalid option -- 'x'`, exit `1`, nothing touched | supported surface is `D28` |
| Directory that is a mount point | `rm -r` descends and removes contents | refused (`is a mount point`) | `rename()` cannot move a mount point |
| Directory containing a mount point | `rm -r` descends into it (unless `--one-file-system`) | refused (`D29`) | the mount would move into the trash |
| A path that resolves to the current directory | removed (only literal `.` and `..` are refused) | refused | a dangling cwd breaks every later command in that shell |
| Volume without a trash | deletes permanently | error, nothing deleted | there is no delete path (`D33`) |
| Exit code on usage error | `1` | `1` | — |

## 5. CLI contract

### 5.1 Invocation grammar

```
trash [FLAGS] [--] TARGET...
```

`trash` is an `rm` drop-in for the flags in `§ 5.2`: every argument is a path,
and every flag it accepts means what it means in `rm`. Flags outside `D28` are
rejected, not ignored.
There are no subcommands. Every non-flag argument is a path, so a
file named `list` is trashed with plain `trash list`. `--` always ends flag
parsing.

With no targets the run is a usage error (`trash: missing operand`), exit `1`. A
single `-` is a path, not a flag. Flags may be clustered (`-rf`, `-Rv`). No flag
takes a value, so `--flag=value` is never valid. `--help` and `--version` win
over everything else: they print and exit `0` before any target is examined.

### 5.2 Flags

| Flag | Argument | Behavior |
| --- | --- | --- |
| `-f`, `--force` | — | Ignore missing targets: no message, no exit-status change. POSIX `-f` only, nothing more |
| `-r`, `-R` | — | Required when the target is a real directory; a symlink is trashed as a link and never needs it. A trailing slash means "must be a directory", so a symlink with one fails with `Not a directory` |
| `-d`, `--dir` | — | Trash an empty directory without `-r`; a non-empty directory fails with `Directory not empty`. A symlink is trashed as a link, with no emptiness check |
| `-v`, `--verbose` | — | Print `trashed 'PATH'` for every target that was moved |
| `--help` | — | Usage on stdout, exit `0`. Contains the synopsis, the flag list, the exit status, and the note that unsupported `rm` flags are rejected |
| `--version` | — | `trash <version>` on stdout, exit `0`; `<version>` is the `version:` field of `v.mod` |
| `--` | — | End of flags |

`/` and every other filesystem root are always refused; there is no
`--preserve-root` or `--no-preserve-root` flag (`§ 9`).

Any other flag, including flags `rm` accepts, is a usage error: one line on
stderr, exit `1`, nothing is trashed.

### 5.3 Interaction

There are no prompts. `-i`, `-I` and `--interactive` are not supported (`D4`), and
`-f` has only its POSIX meaning, so the CLI never reads stdin. A run that would
need a decision the user did not express on the command line fails instead of
asking (`§ 5.5`).

### 5.4 Diagnostics and exit status

- Errors: `trash: cannot trash 'PATH': REASON` on stderr, one per failed entry.
  A failure of one entry never stops the remaining entries.
- `PATH` is the argument exactly as the user typed it, wrapped in `'…'`.
- `REASON` for OS errors is `strerror(errno)` or the platform equivalent, so its
  wording is locale-dependent. Only the fixed parts of a message are stable and
  may be asserted in tests; the messages the tool itself composes (`no usable
  trash directory on this volume`, `Directory not empty`, `Not a directory`,
  `missing operand`, `invalid option`) are not localized.
- `-f` suppresses `ENOENT` only, and only for targets that do not exist.
- Exit `0` if no entry failed; `1` otherwise.
- `-v` prints one line per processed target: `trashed 'PATH'`.
- Nothing is written to stdout except `--help`, `--version` and the `-v` lines.
- Unsupported short flags print `trash: invalid option -- 'x'`; unsupported long
  flags, including `--flag=value` forms, print
  `trash: unrecognized option '--long'`. Both are one line on stderr, exit `1`,
  nothing trashed.
- When both `--help` and `--version` are given, `--help` wins.

#### Composed reasons

The reasons `trash` composes itself (everything except the OS text) are fixed,
English and not localized. `REASON` in `trash: cannot trash 'PATH': REASON` and
`PutResult.reason` use exactly these strings:

| Kind | Reason |
| --- | ------ |
| OS error | `strerror(errno)` / the platform equivalent |
| filesystem root | `refusing to trash a filesystem root` |
| current directory | `refusing to trash the current directory` |
| `.` or `..` as the last component | `refusing to trash '.' or '..'` |
| trash directory or its ancestor | `refusing to trash the trash directory or one of its ancestors` |
| mount point | `is a mount point` |
| directory that contains a mount point | `contains a mount point` |
| unreadable mount table | `cannot read the mount table` |
| directory without `-r` | `Is a directory` |
| non-directory with a trailing slash | `Not a directory` |
| non-empty directory with `-d` | `Directory not empty` |
| no usable trash on the volume | `no usable trash directory on this volume` |
| the entry changed after the guards | `the target changed during the operation` |
| no free collision name | `no name available in the trash directory` |
| path over the shell API limit (Windows) | `path too long for the Recycle Bin` |
| reserved device name, `:`, trailing dot or space (Windows) | `invalid path for the Recycle Bin` |
| object larger than the Recycle Bin quota (Windows) | `the object does not fit in the Recycle Bin` |

### 5.5 Refusal instead of deletion

Some targets cannot be trashed: a volume with no usable trash directory, a
network share with no Recycle Bin, an object larger than the Recycle Bin quota.
`trash` never deletes such an object (`D33`). It reports an error and leaves
everything in place:

```
trash: cannot trash 'PATH': no usable trash directory on this volume
```

- Exit status `1`, like any other failure.
- Nothing is printed on stdout, nothing is read from stdin.
- `-f` does not change this: it only silences "no such file or directory".
- The same rule applies to the library: `put` reports the failure in
  `PutResult.reason` and never destroys data.

## 6. Library API

`module trash`: non-interactive (it never reads stdin), no global state, safe to
call from multiple threads with distinct paths (no shared mutable data; Windows
COM is initialized per thread, `D35`).

```v
pub struct PutOptions {
pub mut:
	force     bool // `-f`: ignore missing targets
	recursive bool // `-r`/`-R`: a real directory may be trashed
	dir       bool // `-d`/`--dir`: an empty directory may be trashed without `-r`
}

pub struct PutResult {
pub:
	path       string // target as given by the caller
	trashed    bool   // the object is in the trash
	trash_path string // absolute path inside the trash; '' when not trashed
	reason     string // human-readable failure reason; '' on success
}

pub fn put(targets []string, opts PutOptions) []PutResult
```

- `PutOptions` mirrors the CLI flags (`D38`); the directory rules of `§ 5.2` are
  applied by `put`, so a library caller gets the same refusals as the CLI.
- `PutOptions` is `@[params]`: the argument may be omitted (`put(paths)`) or
  passed as named fields (`put(paths, recursive: true)`).
- On Windows `trash_path` is `''` even on success (`D46`).

- `put` never returns an error type: every target yields a `PutResult`, failures
  are reported per item, matching `rm`'s continue-after-error semantics.
- Guards and collision handling live in the module, not in the CLI: library
  users get the same safety. The CLI only parses flags and maps results to exit
  status.
- The refusal policy of `§ 5.5` is part of `put`, not of the CLI.
- `list`, `restore` and `empty` are not supported (`D17`).
- `PutResult.reason` is the bare reason: no `trash:` prefix, no path. The CLI
  renders it as `trash: cannot trash 'PATH': REASON`.
- `-v` is a CLI concern: `put` reports `PutResult.trash_path`, the CLI prints it.

## 7. Architecture

Policy never leaks into a backend: a backend receives a resolved `Target`
(`§ 7.1`) and returns where the object ended up, or a typed error. It knows
nothing about flags, guards or `rm`.

### 7.1 Backend contract

```v
// Unix. Windows uses `{ abs_path string }` instead: the shell API resolves paths
// itself (`§ 8.3`).
struct Target {
	dir_fd int    // directory holding the entry, already walked with O_NOFOLLOW
	name   string // the entry's basename
	st_dev u64    // device of the entry, from fstatat
	st_ino u64    // inode of the entry, checked again right before the move
}

struct Placed {
pub:
	trash_path string
}
```

Each platform exposes `put(target Target) !Placed` as a free function in
`internal/<platform>`; `nix_backend_put` dispatches between `freedesktop` and
`darwin`. There is no V interface: the platform is chosen at compile time, so
an interface would only add a layer.

Backends must:

- never follow a symlink at `target.name`;
- re-check `st_dev`/`st_ino` immediately before the move and fail with
  `the target changed during the operation` if the entry is no longer the
  guarded one;
- be atomic when source and trash are on the same filesystem;
- leave no payload without its metadata (Linux ordering, `§ 8.1`);
- return typed errors, never panic, never write to stdout/stderr;
- be usable without a terminal, a GUI session or a network.

### 7.2 Filesystem access on Unix

Path-based checks followed by a path-based `rename` are a race. Every access to
the target therefore goes through directory descriptors:

- split the argument into a parent part and the final component, and resolve the
  parent once with `realpath(3)`. This is the only place where a symlink in the
  middle of the path is followed, which is what makes `trash /tmp/x` behave like
  `rm /tmp/x` on systems where `/tmp` is a symlink;
- descend the resolved parent one component at a time with
  `openat(fd, name, O_NOFOLLOW | O_DIRECTORY | O_CLOEXEC)`, starting from `/`.
  A component that became a symlink after `realpath` fails here, which is what
  closes the race;
- the final component is never opened: its type and identity come from
  `fstatat(dirfd, name, AT_SYMLINK_NOFOLLOW)`, so a symlink as the last
  component is trashed as a link, exactly like `rm`;
- every guard in `§ 9` is evaluated from that `fstatat` result (`st_dev`,
  `st_ino`, mode, mount table) and never from a re-parsed path string;
- the move is `renameat(src_dirfd, name, files_dirfd, name)`;
- the mount-point guard (`D29`) compares the target's canonical path, taken from
  the descriptor chain (`/proc/self/fd/N` on Linux, `fcntl(F_GETPATH)` on macOS),
  with the mount table, whose escapes (`\040`, `\011`, `\134`) are decoded first
  (`D36`); the path is the canonical path of the parent descriptor plus `/` plus
  `name`, because the final component is never opened (`D40`);
- a symlink that appears in an intermediate component after the `realpath` call
  is never followed: the open fails (`ELOOP`, or `ENOTDIR` where the platform
  reports it that way) and is reported as an error;
- a final component of `.` or `..` is refused before the descent (`D42`);
- trash directories are opened the same way (`O_NOFOLLOW | O_DIRECTORY`) and
  validated with `fstat` before use: a real directory, owned by the effective
  uid, and on the same `st_dev` as the source.

The two places that do open a final component are the emptiness check for `-d`
(`O_DIRECTORY | O_NOFOLLOW`, `readdir` only) and the directories of the trash
itself, which are opened by path, not by descent.

The Windows backend does not use this layer: it hands paths to the shell API,
which has its own resolution rules (`§ 8.3`).

## 8. Platform backends

### 8.1 Linux — freedesktop.org Trash specification

`$topdir` is the mount point of the volume that contains the trash directory.

Trash directory resolution for a target on volume `$topdir`:

1. `$XDG_DATA_HOME/Trash` (default `$HOME/.local/share/Trash`) when the target is
   on the same volume as **that directory**, not merely the same volume as
   `$HOME`. A relative `$XDG_DATA_HOME` is ignored; if `$HOME` is unset and
   `$XDG_DATA_HOME` does not name an absolute path, this candidate is skipped.
   When `Trash` itself is missing it is created (0700) if and only if
   `$XDG_DATA_HOME` already exists and lies on the target's volume; if
   `$XDG_DATA_HOME` is missing the candidate is skipped (`D43`).
2. `$topdir/.Trash/$uid`, only if `$topdir/.Trash` exists, is a real directory
   (not a symlink) with the sticky bit set, and `$topdir/.Trash/$uid` exists, is
   a real directory (not a symlink) and is owned by `$uid`.
3. `$topdir/.Trash-$uid`: opened if it already exists, otherwise created with
   `mkdirat(..., 0700)`. `EEXIST` is not an error: the directory is opened and
   validated like the others, which is what catches a pre-planted symlink.
4. Otherwise: the object is refused with `no usable trash directory on this
   volume` (`§ 5.5`).

Each candidate is opened with `O_NOFOLLOW | O_DIRECTORY` and accepted only if
`fstat` reports a directory owned by the effective uid whose `st_dev` equals the
source's; otherwise the next candidate is tried. A candidate that cannot be
opened (missing, `EACCES`, wrong owner, symlink) is skipped, not reported.
Inside the trash directory: `files/` and `info/`, both `0700`, opened and
validated the same way. Every created directory is `mkdirat(..., 0700)` followed
by `fchmod(0700)` on the opened descriptor, so the umask cannot change the
result; directories that already exist are only validated, never re-`chmod`ed.

For every trashed object, in this order:

1. pick a candidate `name` from the basename of the target. When
   `len(name) + len('.trashinfo')` would exceed `NAME_MAX` (`pathconf(info_fd,
   _PC_NAME_MAX)`, `255` when it cannot be queried), shorten `name` first
   (`D44`): split off the extension (the last `.` that is not at position 0),
   truncate the stem to `NAME_MAX - 9 - len(extension)` bytes on a UTF-8
   boundary and append the extension; when the extension leaves no room for at
   least one byte of stem, truncate the whole name to `NAME_MAX - 9` bytes on a
   UTF-8 boundary instead;
2. create `info/<name>.trashinfo` with
   `openat(info_fd, ..., O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
   0600)`. `O_EXCL` both reserves the name against concurrent runs and refuses
   a pre-planted symlink; `EEXIST` returns to step 1 with the next name
   (`a.txt` → `a.txt.1`, `.2`, … appended to the whole name);
3. write the content, `fsync` the descriptor, close it. A write or `fsync`
   failure removes the info file and is reported as an error;
4. re-check `fstatat` of the target against the guarded `st_dev`/`st_ino`.
   A mismatch removes the info file and fails with `the target changed during
   the operation`; then move the payload with a no-replace rename into
   `files/<name>` (`D32`).
   `EEXIST` removes the info file and returns to step 1 with the next name; any
   other failure removes the info file and is reported as an error.

The collision loop is bounded at 1000 attempts; after that the candidate is
reported as `no name available in the trash directory` instead of looping
indefinitely.

A process killed between steps 3 and 4 leaves an info file without a payload.
That state is harmless: no data is lost, the item is absent from the trash, and
any tool that cleans broken items can remove the file.

The content has exactly two keys, in this order, `\n` line endings:

```
[Trash Info]
Path=<percent-encoded path relative to $topdir>
DeletionDate=<YYYY-MM-DDTHH:MM:SS>
```

- `Path` is relative to `$topdir`, without a leading `/` (`D45`), and
  percent-encoded byte-wise: bytes in `A-Za-z0-9-_.~/` stay literal, everything
  else becomes `%XX` (uppercase hex);
- `DeletionDate` is **local time** with no timezone and no fractional seconds.

### 8.2 macOS

Primary path: `NSFileManager.defaultManager.trashItemAtURL:resultingItemURL:error:`
with a `file://` `NSURL` for the absolute path. This moves the object to the
right trash for its volume (`~/.Trash` on the boot volume, `/.Trashes/<uid>` on
others) and records the original location, so Finder's "Put Back" works. The
system also picks the name when an item with that name is already in the trash:
for example, on macOS 15 a second `dup.txt` became
`dup.txt 10-03-08-302.txt`. The suffix is neither reproduced nor predicted; the
URL returned by the API is reported.

- Interop lives in `internal/darwin/*.c.v` with `#flag darwin -framework
  Foundation`; the message send is declared with the exact signature in one
  place only.
- Every interop call is wrapped in `objc_autoreleasePoolPush/Pop`.
- The returned `resultingItemURL` is reported as `trash_path`.
- A `trashItemAtURL` failure is the error for that target (`D37`). There is no
  `rename` fallback, nothing is copied across volumes, and collisions are left
  entirely to the system.
- Trashing a mount point is refused (`§ 9`).
- The guarded `st_dev`/`st_ino` are checked again immediately before the call;
  the path-based API still leaves a narrow window. This residual window is
  accepted because the system trash API has no descriptor form.

### 8.3 Windows

`IFileOperation`:

- `CoInitializeEx(COINIT_APARTMENTTHREADED)` on the calling thread; if COM was
  already initialized there, `CoUninitialize` is not called (`D35`);
- `CoCreateInstance(CLSID_FileOperation)`;
- `SetOperationFlags(FOF_ALLOWUNDO | FOF_NO_UI)`, where `FOF_ALLOWUNDO` is what
  routes the operation to the Recycle Bin; the `HRESULT` is checked, and a
  failure abandons the whole batch instead of risking a permanent delete;
- one `SHCreateItemFromParsingName` + `DeleteItem` per target;
- `PerformOperations`, then `GetAnyOperationsAborted`; an aborted operation is
  an error for every item of that batch;
- a failing `DeleteItem` is reported per item; the batch still runs.

Objects larger than the Recycle Bin quota, and paths on volumes with no Recycle
Bin (UNC/network shares), are **refused** with an error (`§ 5.5`, `D18`, `D19`).
The quota is checked **before** the operation (`SHQueryRecycleBinW` plus the
volume's `BitBucket` capacity), because `IFileOperation` would otherwise delete
permanently without notice; for a directory this means computing its total
size first, which is the only place where Windows walks a tree.
`FOF_WANTNUKEWARNING` is not used: it opens a GUI dialog.

Quota details (`D47`): the capacity is the `MaxCapacity` value under
`HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume\{GUID}`;
when the key or the value is missing the Windows default applies (10% of the
volume below 40 GB, 5% otherwise). The object is refused when
`size + used > capacity`, where `used` is `i64Size` from
`SHQueryRecycleBinW`. A directory's size is the sum of the logical file sizes
of its entries; reparse points are not descended and count as zero; a hard link
counts once per directory entry. Because `IFileOperation` moves the whole batch,
the check uses the total size of the accepted items per volume, not the size of
one item at a time. Every UNC path (`\\server\share\...`) is
refused with `no usable trash directory on this volume`.

The resulting Recycle Bin path is not reported: `PutResult.trash_path` is `''`
on Windows (`D46`).

Collisions are resolved by the OS (Explorer renames on restore), not by this
tool. A volume mount point nested inside a directory travels as a reparse
point, so no tree check is needed here (`D29`).

The shell API resolves paths itself, so the descriptor-walk protection of
`§ 7.2` has no Windows equivalent. This limitation is accepted; re-implementing
the Recycle Bin writer is rejected by `D11`.

Path rules (`D25`–`D27`, `D48`):

- a path that exceeds the shell API limit (more than 259 UTF-16 code units of
  the absolute path) fails with `path too long for the Recycle Bin`; it is never
  deleted permanently instead;
- a path with a `$Recycle.Bin` component is refused with `refusing to trash the
  trash directory or one of its ancestors`;
- junctions are detected with `FILE_ATTRIBUTE_REPARSE_POINT` (V's `os.is_link`
  does not report them) and are never descended into; the reparse point is
  trashed as a link. The target is read with `FSCTL_GET_REPARSE_POINT`: if the
  substitute name is a volume root (`\??\Volume{...}\` or `\??\X:\`) the
  entry is refused as a mount point (`§ 9`), otherwise it is trashed as-is;
- reserved device names (`CON`, `PRN`, `AUX`, `NUL`, `COM1`–`COM9`, `LPT1`–
  `LPT9`), a `:` anywhere after the drive prefix, and a last component ending in
  a dot or a space are rejected with `invalid path for the Recycle Bin` before
  any API call.

## 9. Safety guards

Refused in every mode, on every platform, with an error and exit `1`:

- `/` and any filesystem root (`C:\`, `\\server\share\`);
- `.` and `..` as the last component (`D42`), and any path that resolves to the
  current directory;
- the trash directory itself and any of its ancestors, compared against every
  candidate path for the target's volume, not only the one that would be used;
- any path that is a mount point;
- a directory that contains a mount point anywhere below it, on Linux and
  macOS (`D29`); the mount table is the source of truth, not a tree walk;
- when the mount table cannot be read at all (`D41`);
- on Windows: a reparse point that resolves to a volume root, an absolute path
  longer than the shell API limit, a `$Recycle.Bin` component, a reserved device
  name, a path containing `:`, and a name ending in a dot or a space
  (`D25`–`D27`).

Never followed: symlinks (the link itself is trashed), junctions on Windows.
A directory is moved as a single object and its contents are never enumerated;
the only exceptions are the emptiness check for `-d` and the size computation
required by the Windows quota check (`§ 8.3`).

On Unix every check is evaluated from `fstatat`/`fstat` on the descriptor chain
(`§ 7.2`), never from a re-parsed path string. All guards are evaluated before
any trash directory is created or opened; enumerating the candidate trash paths
is read-only and happens before the guards, creating them happens after.
