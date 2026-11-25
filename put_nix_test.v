module trash

import internal.fsx
import internal.pathx
import os
import time

// temp_root creates a directory outside the repository and outside the real
// trash; every test removes it again.
fn temp_root() !string {
	// The sandbox lives on the resolved temp path, so a failure here is never
	// about the shape of `os.temp_dir()` itself.
	dir := os.join_path(os.real_path(os.temp_dir()), 'trash_guard_${os.getpid()}_${time.now().unix_nano()}')
	os.mkdir_all(dir)!
	return dir
}

// guard_reason runs the descriptor walk and the guards and returns the reason
// of the first refusal, or '' when the target is accepted.
fn guard_reason(arg string, opts PutOptions, ctx GuardContext) string {
	res := resolve_target(arg) or { return 'resolve: ${err.msg()}' }
	defer {
		fsx.close(res.dir_fd)
	}
	check_guards(res, pathx.parse(arg), opts, ctx) or { return err.msg() }
	return ''
}

fn no_context() GuardContext {
	return GuardContext{}
}

fn test_root_and_dot_components_are_refused_before_the_walk() {
	assert put(['/'], recursive: true)[0].reason == 'refusing to trash a filesystem root'
	assert put(['//'], recursive: true)[0].reason == 'refusing to trash a filesystem root'
	assert put(['.'], recursive: true)[0].reason == "refusing to trash '.' or '..'"
	assert put(['..'], recursive: true)[0].reason == "refusing to trash '.' or '..'"
	assert put(['a/.'], recursive: true)[0].reason == "refusing to trash '.' or '..'"
}

fn test_missing_target_is_an_error_unless_forced() {
	root := temp_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	missing := os.join_path(root, 'nope')
	result := put([missing])[0]
	assert !result.trashed
	assert result.reason != ''

	forced := put([missing], force: true)[0]
	assert !forced.trashed
	assert forced.reason == ''
}

fn test_directory_rules() {
	root := temp_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	os.mkdir_all(os.join_path(root, 'empty'))!
	os.mkdir_all(os.join_path(root, 'full'))!
	os.write_file(os.join_path(root, 'full', 'x'), '')!
	os.write_file(os.join_path(root, 'file'), '')!
	os.symlink('empty', os.join_path(root, 'link'))!

	empty := os.join_path(root, 'empty')
	full := os.join_path(root, 'full')
	file := os.join_path(root, 'file')
	link := os.join_path(root, 'link')

	assert guard_reason(empty, PutOptions{}, no_context()) == 'Is a directory'
	assert guard_reason(full, PutOptions{}, no_context()) == 'Is a directory'
	assert guard_reason(full, PutOptions{ dir: true }, no_context()) == 'Directory not empty'
	assert guard_reason(empty, PutOptions{ dir: true }, no_context()) == ''
	assert guard_reason(full, PutOptions{ recursive: true }, no_context()) == ''
	assert guard_reason(empty, PutOptions{ dir: true, recursive: true }, no_context()) == ''
	assert guard_reason(file, PutOptions{}, no_context()) == ''
	assert guard_reason(link, PutOptions{}, no_context()) == ''
}

fn test_trailing_slash_requires_a_directory() {
	root := temp_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	os.write_file(os.join_path(root, 'file'), '')!
	os.symlink('file', os.join_path(root, 'link'))!
	assert guard_reason('${root}/file/', PutOptions{}, no_context()) == 'Not a directory'
	assert guard_reason('${root}/link/', PutOptions{}, no_context()) == 'Not a directory'
	assert guard_reason('${root}/', PutOptions{ recursive: true }, no_context()) == ''
}

fn test_current_directory_is_refused() {
	root := temp_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	os.mkdir_all(os.join_path(root, 'cwd'))!
	old := os.getwd()
	os.chdir(os.join_path(root, 'cwd'))!
	defer {
		os.chdir(old) or {}
	}
	assert guard_reason(os.join_path(root, 'cwd'), PutOptions{ recursive: true },
		no_context()) == 'refusing to trash the current directory'
}

fn test_mount_point_guards() {
	root := temp_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	os.mkdir_all(os.join_path(root, 'vol'))!
	os.mkdir_all(os.join_path(root, 'vol', 'inner'))!
	vol := os.join_path(root, 'vol')

	assert guard_reason(vol, PutOptions{ recursive: true }, GuardContext{
		mounts: [vol]
	}) == 'is a mount point'

	assert guard_reason(vol, PutOptions{ recursive: true }, GuardContext{
		mounts: [os.join_path(vol, 'inner')]
	}) == 'contains a mount point'

	// A mount point that is not below the target is irrelevant.
	assert guard_reason(vol, PutOptions{ recursive: true }, GuardContext{
		mounts: ['/somewhere/else']
	}) == ''
}

fn test_trash_directory_and_its_ancestors_are_refused() {
	root := temp_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	os.mkdir_all(os.join_path(root, 'data', 'Trash'))!
	data := os.join_path(root, 'data')

	assert guard_reason(data, PutOptions{ recursive: true }, GuardContext{
		candidates: [os.join_path(data, 'Trash')]
	}) == 'refusing to trash the trash directory or one of its ancestors'

	assert guard_reason(data, PutOptions{ recursive: true }, GuardContext{
		candidates: ['/unrelated/Trash']
	}) == ''
}

fn test_symlinked_directory_in_the_middle_is_followed() {
	root := temp_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	os.mkdir_all(os.join_path(root, 'real'))!
	os.write_file(os.join_path(root, 'real', 'x'), '')!
	os.symlink('real', os.join_path(root, 'link'))!

	// Like `rm`, a symlink in the middle is resolved; only the last component
	// is never followed.
	assert guard_reason(os.join_path(root, 'link', 'x'), PutOptions{}, no_context()) == ''
	// The link itself is trashed as a link.
	assert guard_reason(os.join_path(root, 'link'), PutOptions{}, no_context()) == ''
	// A dangling link in the middle is still an error.
	dangling := guard_reason(os.join_path(root, 'link', 'missing'), PutOptions{}, no_context())
	assert dangling.starts_with('resolve: '), 'got: ${dangling}'
}

fn test_a_symlinked_temp_directory_is_accepted() {
	// `os.temp_dir()` may itself sit behind a symlink (`/var` on macOS, `/tmp`).
	// That must not matter: the parent is resolved before the walk.
	raw := os.join_path(os.temp_dir(), 'trash_symlink_${os.getpid()}_${time.now().unix_nano()}')
	os.mkdir_all(raw)!
	defer {
		os.rmdir_all(raw) or {}
	}
	os.write_file(os.join_path(raw, 'f'), '')!
	assert guard_reason(os.join_path(raw, 'f'), PutOptions{}, no_context()) == ''
}

fn test_dot_in_the_middle_is_accepted() {
	root := temp_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	os.mkdir_all(os.join_path(root, 'a', 'b'))!
	os.write_file(os.join_path(root, 'a', 'b', 'x'), '')!
	assert guard_reason('${root}/a/./b/x', PutOptions{}, no_context()) == ''
	assert guard_reason('${root}/a/b/../b/x', PutOptions{}, no_context()) == ''
}
