#!/usr/bin/env -S v run

// Task runner for this repository, built on `x.imp`.
//
//   ./make.vsh            # fast development build, bin/trash-dev (flow `build`)
//   ./make.vsh ci         # the full gate: fmt, vet, test, release build
//   ./make.vsh release    # only the optimised build, bin/trash
//   ./make.vsh test       # only the tests
//   ./make.vsh install    # release build, then binary, man page, completions
//   ./make.vsh uninstall  # remove what `install` put into PREFIX
//   ./make.vsh clean      # remove both build products
//   ./make.vsh --help     # every flow and flag
//
// `build` is the default on purpose: it is what a developer wants most of the
// time, and it compiles in a fraction of the time `-prod` needs. The gate and
// `install` use `release`, which is the same command with `-prod` into its own
// file, so the two products never invalidate each other and both keep the mtime
// skip.
//
// `install` and `uninstall` honour `PREFIX` (default `/usr/local`) and `DESTDIR`
// (default empty, for staged packaging):
//
//   PREFIX=$HOME/.local ./make.vsh install
//   DESTDIR=/tmp/pkg PREFIX=/usr ./make.vsh install
//   PREFIX=$HOME/.local ./make.vsh uninstall
//
// Every flow runs with the repository root as the working directory, whichever
// directory the script was started from.
import os
import x.imp

// Both products live in `bin/`, which is the build output directory: the
// optimised binary keeps the plain name, the development one carries `-dev`.
// Separate paths keep the mtime skip valid for both.
const dev_target = $if windows { 'bin/trash-dev.exe' } $else { 'bin/trash-dev' }
const release_target = $if windows { 'bin/trash.exe' } $else { 'bin/trash' }

// `takes` is what the mtime skip looks at; a new top-level source directory or
// root source file must be added here, or a local build can be skipped as up to
// date.
const sources = [
	'v.mod'
	'trash.v'
	'options.v'
	'errors.v'
	'put_nix.v'
	'put_linux.v'
	'put_darwin.v'
	'put_windows.v'
	'cmd'
	'internal'
	'trashcli',
]

// InstallPaths is where `install` puts things, after `PREFIX` and `DESTDIR`.
struct InstallPaths {
	root string
	bin  string
	man  string
	bash string
	zsh  string
	fish string
}

// cmd returns a flow body that announces the command and runs it with inherited
// standard streams, so the output appears while it is produced.
fn cmd(args []string) imp.FlowFn {
	return fn [args] (self imp.Flow) ! {
		println('❯ ${args.join(' ')}')
		imp.system_args(args)!
	}
}

// install_paths applies `PREFIX` and `DESTDIR` to the standard Unix layout.
fn install_paths() InstallPaths {
	prefix := os.getenv_opt('PREFIX') or { '/usr/local' }
	destdir := os.getenv_opt('DESTDIR') or { '' }
	root := destdir + prefix
	return InstallPaths{
		root: root
		bin:  '${root}/bin'
		man:  '${root}/share/man/man1'
		bash: '${root}/share/bash-completion/completions'
		zsh:  '${root}/share/zsh/site-functions'
		fish: '${root}/share/fish/vendor_completions.d'
	}
}

// install_file copies one artefact and gives it the mode it needs.
fn install_file(src string, dst string, mode int) ! {
	os.cp(src, dst)!
	os.chmod(dst, mode)!
	println('installed ${dst}')
}

// remove_file deletes one installed artefact and says what it found. A missing
// file is not an error, so `uninstall` stays idempotent.
fn remove_file(path string) ! {
	if os.is_dir(path) {
		return error('`${path}` is a directory, refusing to remove it')
	}
	if os.exists(path) || os.is_link(path) {
		os.rm(path)!
		println('removed ${path}')
		return
	}
	println('not installed: ${path}')
}

// install_flow builds the binary and copies it with the man page and the shell
// completions into `PREFIX`. It does not call `sudo`: run the whole script as
// root when the prefix needs it.
fn install_flow() imp.FlowFn {
	return fn (self imp.Flow) ! {
		$if windows {
			return error('install is not supported on Windows; copy ${release_target} yourself')
		}
		paths := install_paths()
		println('installing into ${paths.root}')
		for dir in [paths.bin, paths.man, paths.bash, paths.zsh, paths.fish] {
			os.mkdir_all(dir)!
		}
		install_file(release_target, '${paths.bin}/trash', 0o755)!
		install_file('trash.1', '${paths.man}/trash.1', 0o644)!
		install_file('completions/trash.bash', '${paths.bash}/trash', 0o644)!
		install_file('completions/trash.zsh', '${paths.zsh}/_trash', 0o644)!
		install_file('completions/trash.fish', '${paths.fish}/trash.fish', 0o644)!
	}
}

// uninstall_flow removes exactly the five files `install` writes and nothing
// else: no directory is touched, so a prefix shared with other packages keeps
// its own files. Like `install` it never calls `sudo`.
fn uninstall_flow() imp.FlowFn {
	return fn (self imp.Flow) ! {
		$if windows {
			return error('uninstall is not supported on Windows; remove the binary yourself')
		}
		paths := install_paths()
		if paths.root == '' || paths.root == '/' {
			return error('refusing to uninstall from `${paths.root}`; set PREFIX')
		}
		println('uninstalling from ${paths.root}')
		remove_file('${paths.bin}/trash')!
		remove_file('${paths.man}/trash.1')!
		remove_file('${paths.bash}/trash')!
		remove_file('${paths.zsh}/_trash')!
		remove_file('${paths.fish}/trash.fish')!
	}
}

fn main() {
	os.chdir(@VMODROOT) or {
		eprintln('cannot enter ${@VMODROOT}: ${err.msg()}')
		exit(1)
	}
	mut ctx := imp.new()
	ctx.add_target(dev_target)
	ctx.add_target(release_target)
	ctx.add_flow(
		id:    'fmt'
		help:  'fail if anything is unformatted'
		check: .none
		flow:  cmd(['v', 'fmt', '-verify', '.'])
	)
	ctx.add_flow(
		id:    'vet'
		help:  'vet the whole module, warnings are errors'
		check: .none
		flow:  cmd(['v', 'vet', '-W', '.'])
	)
	ctx.add_flow(
		id:    'test'
		help:  'run the tests'
		check: .none
		flow:  cmd(['v', 'test', '.'])
	)
	ctx.add_flow(
		id:    'build'
		help:  'build ${dev_target} without -prod, for quick testing'
		takes: sources
		gives: [dev_target]
		flow:  cmd(['v', '-o', dev_target, './cmd/trash'])
	)
	ctx.add_flow(
		id:    'release'
		help:  'build ${release_target} with -prod'
		takes: sources
		gives: [release_target]
		flow:  cmd(['v', '-prod', '-o', release_target, './cmd/trash'])
	)
	ctx.add_flow(
		id:    'ci'
		help:  'the full gate'
		check: .none
		pre:   [
			imp.FlowDep{ id: 'fmt' },
			imp.FlowDep{ id: 'vet' },
			imp.FlowDep{ id: 'test' },
			imp.FlowDep{ id: 'release' },
		]
		flow:  fn (self imp.Flow) ! {}
	)
	ctx.add_flow(
		id:    'check'
		help:  'alias of ci'
		check: .none
		pre:   [imp.FlowDep{ id: 'ci' }]
		flow:  fn (self imp.Flow) ! {}
	)
	ctx.add_flow(
		id:    'install'
		help:  'release build, then install into PREFIX (default /usr/local)'
		check: .none
		pre:   [imp.FlowDep{ id: 'release' }]
		flow:  install_flow()
	)
	ctx.add_flow(
		id:    'uninstall'
		help:  'remove what install put into PREFIX'
		check: .none
		flow:  uninstall_flow()
	)
	ctx.add_auto_flow(.clean)
	ctx.default(['build'])
	ctx.flow()
}
