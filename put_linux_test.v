module trash

import internal.freedesktop
import internal.pathx
import os
import time

// expected_rel returns the `.trashinfo` Path for an absolute, canonical target
// on its own volume, whatever the mount layout of the test machine is.
fn expected_rel(abs string) string {
	mounts := pathx.system_mounts() or { panic(err) }
	mut normalized := []string{cap: mounts.len}
	for m in mounts {
		normalized << pathx.normalize(m)
	}
	return freedesktop.relative_to(pathx.topdir(abs, normalized), abs)
}

// Sandbox is a temporary work tree plus a temporary `XDG_DATA_HOME`, so the
// tests never touch the real trash.
struct Sandbox {
	root    string
	data    string
	work    string
	old_xdg string
	had_xdg bool
}

fn new_sandbox() !Sandbox {
	// `os.temp_dir()` may sit behind a symlink (`/var` on macOS, `/tmp`); the
	// walk resolves the parent, so the sandbox works either way.
	base := os.temp_dir()
	root := os.join_path(base, 'trash_e2e_${os.getpid()}_${time.now().unix_nano()}')
	data := os.join_path(root, 'data')
	work := os.join_path(root, 'work')
	os.mkdir_all(data)!
	os.mkdir_all(work)!
	old_xdg := os.getenv('XDG_DATA_HOME')
	os.setenv('XDG_DATA_HOME', data, true)
	return Sandbox{
		root:    root
		data:    data
		work:    work
		old_xdg: old_xdg
		had_xdg: old_xdg != ''
	}
}

fn (s Sandbox) trash_root() string {
	return os.join_path(s.data, 'Trash')
}

fn (s Sandbox) info_path(name string) string {
	return os.join_path(s.trash_root(), 'info', '${name}.trashinfo')
}

fn (s Sandbox) payload_path(name string) string {
	return os.join_path(s.trash_root(), 'files', name)
}

fn (s Sandbox) done() {
	if s.had_xdg {
		os.setenv('XDG_DATA_HOME', s.old_xdg, true)
	} else {
		os.unsetenv('XDG_DATA_HOME')
	}
	os.rmdir_all(s.root) or {}
}

fn test_put_file_end_to_end() {
	s := new_sandbox()!
	defer {
		s.done()
	}
	file := os.join_path(s.work, 'a.txt')
	os.write_file(file, 'payload')!
	abs := os.real_path(file)

	results := put([file])
	assert results.len == 1
	assert results[0].trashed
	assert results[0].reason == ''
	assert results[0].trash_path == s.payload_path('a.txt')
	assert !os.exists(file)
	assert os.read_file(s.payload_path('a.txt'))! == 'payload'

	info := os.read_file(s.info_path('a.txt'))!
	rel := freedesktop.encode_path(expected_rel(abs))
	assert info == '[Trash Info]\nPath=${rel}\nDeletionDate=${info.all_after('DeletionDate=')}'
	assert info.contains('DeletionDate=')
}

fn test_trash_layout_modes() {
	s := new_sandbox()!
	defer {
		s.done()
	}
	file := os.join_path(s.work, 'mode.txt')
	os.write_file(file, '')!
	put([file])

	for dir in ['files', 'info'] {
		mode := os.lstat(os.join_path(s.trash_root(), dir))!.mode & 0o777
		assert mode == 0o700, '${dir} must be 0700, got ${mode:o}'
	}
	mode := os.lstat(s.info_path('mode.txt'))!.mode & 0o777
	assert mode == 0o600, '.trashinfo must be 0600, got ${mode:o}'
}

fn test_put_directory_requires_recursive() {
	s := new_sandbox()!
	defer {
		s.done()
	}
	dir := os.join_path(s.work, 'dir')
	os.mkdir_all(os.join_path(dir, 'inner'))!
	os.write_file(os.join_path(dir, 'inner', 'x'), 'x')!

	assert put([dir])[0].reason == 'Is a directory'
	assert os.exists(dir)

	result := put([dir], recursive: true)[0]
	assert result.trashed
	assert !os.exists(dir)
	assert os.exists(os.join_path(result.trash_path, 'inner', 'x'))
}

fn test_collisions_get_a_numeric_suffix() {
	s := new_sandbox()!
	defer {
		s.done()
	}
	os.mkdir_all(os.join_path(s.work, 'one'))!
	os.mkdir_all(os.join_path(s.work, 'two'))!
	first := os.join_path(s.work, 'one', 'dup.txt')
	second := os.join_path(s.work, 'two', 'dup.txt')
	os.write_file(first, 'first')!
	os.write_file(second, 'second')!

	r1 := put([first])[0]
	r2 := put([second])[0]
	assert r1.trash_path == s.payload_path('dup.txt')
	assert r2.trash_path == s.payload_path('dup.txt.1')
	assert os.read_file(r1.trash_path)! == 'first'
	assert os.read_file(r2.trash_path)! == 'second'
	assert os.exists(s.info_path('dup.txt'))
	assert os.exists(s.info_path('dup.txt.1'))
}

fn test_planted_info_symlink_is_not_followed() {
	s := new_sandbox()!
	defer {
		s.done()
	}
	os.mkdir_all(os.join_path(s.trash_root(), 'files'))!
	os.mkdir_all(os.join_path(s.trash_root(), 'info'))!
	outside := os.join_path(s.root, 'outside')
	os.write_file(outside, 'untouched')!
	os.symlink(outside, s.info_path('victim.txt'))!

	file := os.join_path(s.work, 'victim.txt')
	os.write_file(file, 'payload')!
	result := put([file])[0]
	assert result.trashed
	// `O_EXCL` wins over the planted symlink, so the next name is used and the
	// symlink target is left alone.
	assert result.trash_path == s.payload_path('victim.txt.1')
	assert os.read_file(outside)! == 'untouched'
}

fn test_awkward_names_round_trip_through_path() {
	s := new_sandbox()!
	defer {
		s.done()
	}
	name := 'a b%#ä.txt'
	file := os.join_path(s.work, name)
	os.write_file(file, 'x')!
	abs := os.real_path(file)
	result := put([file])[0]
	assert result.trashed

	info := os.read_file(s.info_path(name))!
	encoded := freedesktop.encode_path(expected_rel(abs))
	assert info.contains('Path=${encoded}')
	assert encoded.contains('a%20b%25%23%C3%A4.txt')
}

fn test_put_reports_every_target_independently() {
	s := new_sandbox()!
	defer {
		s.done()
	}
	good := os.join_path(s.work, 'good')
	os.write_file(good, '')!
	missing := os.join_path(s.work, 'missing')

	results := put([missing, good])
	assert results.len == 2
	assert !results[0].trashed
	assert results[0].reason != ''
	assert results[1].trashed
}

// gio_available reports whether a working gvfs trash backend is present.
fn gio_available() bool {
	return os.exec(['gio', 'trash', '--list']).exit_code == 0
}

fn test_gio_sees_the_trashed_item() {
	// Optional interop check: it needs a running gvfs, so it is skipped
	// where `gio trash --list` does not work.
	if !gio_available() {
		return
	}
	s := new_sandbox()!
	defer {
		s.done()
	}
	file := os.join_path(s.work, 'interop.txt')
	os.write_file(file, 'x')!
	assert put([file])[0].trashed
	listing := os.exec(['gio', 'trash', '--list']).output
	assert listing.contains('interop.txt'), 'gio must see the item, got: ${listing}'
}
