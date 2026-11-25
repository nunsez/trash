module testutil

import os
import time

const v_exe = @VEXE
const v_cc = @CCOMPILER

// Sandbox is a temporary work tree, a temporary `XDG_DATA_HOME` and a freshly
// built CLI binary.
pub struct Sandbox {
pub:
	root    string
	data    string
	work    string
	bin     string
	old_xdg string
	had_xdg bool
}

// new_sandbox creates an isolated work tree and builds the CLI into it.
pub fn new_sandbox() !Sandbox {
	// `os.temp_dir()` may sit behind a symlink (`/var` on macOS, `/tmp`); the
	// walk resolves the parent, so the sandbox works either way.
	base := os.temp_dir()
	root := os.join_path(base, 'trash_cli_${os.getpid()}_${time.now().unix_nano()}')
	data := os.join_path(root, 'data')
	work := os.join_path(root, 'work')
	os.mkdir_all(data)!
	os.mkdir_all(work)!
	bin := os.join_path(root, $if windows { 'trash.exe' } $else { 'trash' })
	source := '${@VMODROOT}/cmd/trash'
	mut build := os.exec([v_exe, '-cc', v_cc, '-o', bin, source])
	if build.exit_code != 0 {
		// Some Linux setups cannot link the bundled GC; `-gc none` is enough for
		// a short-lived CLI and keeps the table running.
		build = os.exec([v_exe, '-cc', v_cc, '-gc', 'none', '-o', bin, source])
	}
	if build.exit_code != 0 {
		return error('cannot build the CLI:\n${build.output}')
	}
	old_xdg := os.getenv('XDG_DATA_HOME')
	os.setenv('XDG_DATA_HOME', data, true)
	return Sandbox{
		root:    root
		data:    data
		work:    work
		bin:     bin
		old_xdg: old_xdg
		had_xdg: old_xdg != ''
	}
}

// done restores `XDG_DATA_HOME` and removes the sandbox.
pub fn (s Sandbox) done() {
	if s.had_xdg {
		os.setenv('XDG_DATA_HOME', s.old_xdg, true)
	} else {
		os.unsetenv('XDG_DATA_HOME')
	}
	os.rmdir_all(s.root) or {}
}

// exec runs the CLI in the sandbox work directory and returns exit status and
// both streams.
pub fn (s Sandbox) exec(args []string) os.Result {
	old := os.getwd()
	os.chdir(s.work) or { panic(err) }
	defer {
		os.chdir(old) or {}
	}
	mut command := [s.bin]
	command << args
	return os.exec(command)
}
