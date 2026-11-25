module trash

import os
import time

fn test_put_file_into_the_recycle_bin() {
	dir := os.join_path(os.temp_dir(), 'trash_win_${os.getpid()}_${time.now().unix_nano()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir)!
	defer {
		os.rmdir_all(dir) or {}
	}
	file := os.join_path(dir, 'a.txt')
	os.write_file(file, 'hi')!

	results := put([file])
	assert results.len == 1
	assert results[0].trashed, 'reason: ${results[0].reason}'
	assert results[0].reason == ''
	// The Recycle Bin path is not reported.
	assert results[0].trash_path == ''
	assert !os.exists(file)
}

fn test_windows_refusals() {
	root := put(['C:\\'])[0]
	assert !root.trashed
	assert root.reason == 'refusing to trash a filesystem root'

	share := put(['\\\\server\\share\\x'])[0]
	assert !share.trashed
	assert share.reason == 'no usable trash directory on this volume'

	missing := os.join_path(os.temp_dir(), 'trash_win_missing_${os.getpid()}')
	absent := put([missing])[0]
	assert !absent.trashed
	assert absent.reason != ''

	forced := put([missing], force: true)[0]
	assert !forced.trashed
	assert forced.reason == ''
}

fn test_windows_dot_components_have_their_own_reason() {
	for target in ['.', '..', 'C:\\.', 'C:\\..'] {
		result := put([target], recursive: true)[0]
		assert !result.trashed
		assert result.reason == "refusing to trash '.' or '..'", '${target}: ${result.reason}'
	}
}

fn test_windows_bare_root_is_refused() {
	for target in ['/', '\\'] {
		result := put([target], recursive: true)[0]
		assert !result.trashed
		assert result.reason == 'refusing to trash a filesystem root', '${target}: ${result.reason}'
	}
}

fn test_force_does_not_hide_invalid_paths() {
	invalid := put(['C:\\a\\CON'], force: true)[0]
	assert !invalid.trashed
	assert invalid.reason == 'invalid path for the Recycle Bin'

	long := 'C:\\' + 'a'.repeat(300)
	too_long := put([long], force: true)[0]
	assert !too_long.trashed
	assert too_long.reason == 'path too long for the Recycle Bin'
}

fn test_directory_rules_on_windows() {
	dir := os.join_path(os.temp_dir(), 'trash_win_dir_${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(os.join_path(dir, 'inner'))!
	defer {
		os.rmdir_all(dir) or {}
	}

	refused := put([dir])[0]
	assert refused.reason == 'Is a directory'

	not_empty := put([dir], dir: true)[0]
	assert not_empty.reason == 'Directory not empty'

	trashed := put([dir], recursive: true)[0]
	assert trashed.trashed, 'reason: ${trashed.reason}'
	assert !os.exists(dir)
}
