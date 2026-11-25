module freedesktop

import internal.fsx
import os
import time

fn sandbox_root() !string {
	// The sandbox lives on the resolved temp path, so a failure here is never
	// about the shape of `os.temp_dir()` itself.
	base := os.real_path(os.temp_dir())
	dir := os.join_path(base, 'trash_fd_${os.getpid()}_${time.now().unix_nano()}')
	os.mkdir_all(dir)!
	return dir
}

fn with_xdg(path string) string {
	old := os.getenv('XDG_DATA_HOME')
	os.setenv('XDG_DATA_HOME', path, true)
	return old
}

fn restore_xdg(old string) {
	if old == '' {
		os.unsetenv('XDG_DATA_HOME')
	} else {
		os.setenv('XDG_DATA_HOME', old, true)
	}
}

fn with_home(path string) string {
	old := os.getenv('HOME')
	os.setenv('HOME', path, true)
	return old
}

fn restore_home(old string) {
	if old == '' {
		os.unsetenv('HOME')
	} else {
		os.setenv('HOME', old, true)
	}
}

fn test_candidate_paths_order() {
	root := sandbox_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	data := os.join_path(root, 'data')
	os.mkdir_all(data)!
	old := with_xdg(data)
	defer {
		restore_xdg(old)
	}

	dev := fsx.stat_path(data)!.dev
	uid := os.geteuid()
	paths := candidate_paths('/', dev)
	assert paths[0] == os.join_path(data, 'Trash')
	assert paths[1] == '/.Trash/${uid}'
	assert paths[2] == '/.Trash-${uid}'

	// A data directory on another device is not a candidate for this volume.
	assert candidate_paths('/', dev + 1)[0] == '/.Trash/${uid}'
}

fn test_open_trash_refuses_a_symlinked_home_trash() {
	root := sandbox_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	data := os.join_path(root, 'data')
	os.mkdir_all(data)!
	elsewhere := os.join_path(root, 'elsewhere')
	os.mkdir_all(elsewhere)!
	os.symlink(elsewhere, os.join_path(data, 'Trash'))!
	old := with_xdg(data)
	defer {
		restore_xdg(old)
	}

	dev := fsx.stat_path(data)!.dev
	uid := u32(os.geteuid())
	// A top directory that does not exist rules out candidates 2 and 3.
	assert open_trash(os.join_path(root, 'no-volume'), dev, uid) == none
	// Nothing was created inside the symlink target.
	assert os.ls(elsewhere)!.len == 0
}

fn test_open_trash_creates_the_private_directory() {
	root := sandbox_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	volume := os.join_path(root, 'volume')
	os.mkdir_all(volume)!
	old := with_xdg('')
	defer {
		restore_xdg(old)
	}
	// Without `$XDG_DATA_HOME` the home trash is skipped, so the private
	// per-volume directory is created.
	old_home := with_home('')
	defer {
		restore_home(old_home)
	}
	dev := fsx.stat_path(volume)!.dev
	uid := u32(os.geteuid())
	td := open_trash(volume, dev, uid) or {
		assert false, 'the private trash directory must be created'
		return
	}
	defer {
		fsx.close(td.root_fd)
		fsx.close(td.files_fd)
		fsx.close(td.info_fd)
	}
	expected := os.join_path(volume, '.Trash-${uid}')
	assert td.root == expected
	assert (os.lstat(expected)!.mode & 0o777) == 0o700
	assert os.is_dir(os.join_path(expected, 'files'))
	assert os.is_dir(os.join_path(expected, 'info'))
}

fn test_existing_trash_directories_are_not_rechmoded() {
	root := sandbox_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	volume := os.join_path(root, 'volume')
	os.mkdir_all(volume)!
	old := with_xdg('')
	defer {
		restore_xdg(old)
	}
	old_home := with_home('')
	defer {
		restore_home(old_home)
	}
	uid := u32(os.geteuid())
	private := os.join_path(volume, '.Trash-${uid}')
	files := os.join_path(private, 'files')
	os.mkdir_all(files)!
	os.chmod(files, 0o755)!
	dev := fsx.stat_path(volume)!.dev
	td := open_trash(volume, dev, uid) or {
		assert false, 'the existing private trash directory must be accepted'
		return
	}
	defer {
		fsx.close(td.root_fd)
		fsx.close(td.files_fd)
		fsx.close(td.info_fd)
	}
	// `files/` already existed, so its mode must be left alone.
	assert (os.lstat(files)!.mode & 0o777) == 0o755
	// `info/` was created here, so it gets 0700 whatever the umask is.
	assert (os.lstat(os.join_path(private, 'info'))!.mode & 0o777) == 0o700
}
