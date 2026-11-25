# AGENTS.md

Guidance for automated coding agents and contributors working on `trash`.

## Project

`trash` is a drop-in `rm` replacement for Linux, macOS and Windows. It moves
targets into the **platform's system trash** instead of destroying them, and it
is both a CLI and a V library.

- V 0.5.x, no third-party V modules.
- Licensed under AGPLv3.
- Code, identifiers, comments and documentation are in English.

## Sources of truth

| File | Role |
| ---- | ---- |
| `SPECIFICATION.md` | Architecture, contracts, decisions. The only source of truth |
| `README.md` | Public description |

`SPECIFICATION.md` wins over code, tests and `README.md`. Never keep a second
copy of it. It is not referenced from the source: the code must explain itself.

## Protocol

1. **Read `SPECIFICATION.md` before doing anything.** If the spec does not
   answer a question that the current step needs, stop and ask. Once answered,
   record the answer in `§ 3` before implementing it.
2. **One change at a time.** Implement it, run the gate, and keep the spec in
   sync before moving on.
3. **`rm` parity is the default.** Any intentional difference from `rm` must be
   added to the deviation table in `§ 4` in the same change.
4. **Scope discipline.** No speculative abstractions, no flags, types or options
   that the current step does not need.
5. **Ask before adding dependencies**, before changing the file layout, and
   before any change that contradicts the spec.

## Conventions

- Behavior changes need a test next to the code.
- Platform-specific tests live in `*_<platform>_test.v` files (`_linux`,
  `_darwin`, `_windows`, and `_nix` for Unix-only). Prefer them over runtime
  `$if` guards in shared tests; shared tests must still compile and pass on all
  three platforms.
- A CLI change is not complete until `README.md`, `trash.1`, the shell
  completions and the parity tests are updated in the same change.
- The library returns typed errors and never writes to stdout or stderr. Only the
  CLI prints messages and maps results to exit codes.
- There is deliberately no `make.vsh run` flow. For a manual check, run
  `./bin/trash-dev` directly; never point it at real data.

## Checks

```sh
./make.vsh ci
```

`./make.vsh ci` runs `fmt`, `vet`, `test` and `release` in that order and stops at
the first failure. A change is done when the gate passes and the spec reflects
it. During work, use a single flow (`./make.vsh test`, `./make.vsh build`) or
the plain command (`v fmt -w .`, `v vet -W .`, `v test .`); they are faster than
the gate.

## Safety

- Tests must use a temporary directory and a temporary `XDG_DATA_HOME`. Never
  write into the real system trash.
- Do not delete files that existed before the task without confirmation.
- Do not add C interop outside `internal/darwin`, `internal/windows`, and the
  Unix syscall wrappers of `internal/fsx`/`internal/pathx` (spec `D12`), or
  anywhere the spec does not call for it.
- Do not add a permanent-delete path. An object that cannot be trashed is an
  error.
