module fsx

import os
import time

// temp_root creates a directory outside the repository and outside the real
// trash; every test removes it again.
fn temp_root() !string {
	dir := os.join_path(os.temp_dir(), 'trash_fsx_${os.getpid()}_${time.now().unix_nano()}')
	os.mkdir_all(dir)!
	return dir
}

fn test_open_dir_at_refuses_symlinks_and_files() {
	root := temp_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	os.mkdir_all(os.join_path(root, 'real'))!
	os.symlink('real', os.join_path(root, 'link'))!
	os.write_file(os.join_path(root, 'file'), 'x')!

	root_fd := open_dir(root)!
	defer {
		close(root_fd)
	}

	real_fd := open_dir_at(root_fd, 'real')!
	close(real_fd)

	open_dir_at(root_fd, 'link') or {
		// Linux reports ELOOP, macOS ENOTDIR when O_DIRECTORY is combined with
		// O_NOFOLLOW. Both mean "the symlink was not followed".
		assert is_loop(err) || is_not_dir(err), 'a symlink must not be followed, got: ${err.msg()}'
		return
	}
	assert false, 'opening a symlink as a directory must fail'

	open_dir_at(root_fd, 'file') or {
		assert is_not_dir(err)
		return
	}
	assert false, 'opening a file as a directory must fail'
}

fn test_stat_at_does_not_follow_symlinks() {
	root := temp_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	os.write_file(os.join_path(root, 'file'), 'hello')!
	os.symlink('file', os.join_path(root, 'link'))!
	root_fd := open_dir(root)!
	defer {
		close(root_fd)
	}

	file_st := stat_at(root_fd, 'file')!
	assert file_st.is_file()
	assert !file_st.is_link()
	assert file_st.size == 5

	link_st := stat_at(root_fd, 'link')!
	assert link_st.is_link()
	assert !link_st.is_file()

	stat_at(root_fd, 'missing') or {
		assert is_missing(err)
		return
	}
	assert false, 'stat of a missing entry must fail'
}

fn test_create_excl_at_reserves_the_name() {
	root := temp_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	root_fd := open_dir(root)!
	defer {
		close(root_fd)
	}

	fd := create_excl_at(root_fd, 'a.trashinfo', 0o600)!
	write_all(fd, '[Trash Info]\n')!
	sync(fd)!
	close(fd)

	create_excl_at(root_fd, 'a.trashinfo', 0o600) or {
		assert is_exist(err)
		return
	}
	assert false, 'O_EXCL must refuse an existing name'
}

fn test_rename_noreplace_never_overwrites() {
	root := temp_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	os.mkdir_all(os.join_path(root, 'src'))!
	os.mkdir_all(os.join_path(root, 'dst'))!
	os.write_file(os.join_path(root, 'src', 'a'), 'new')!
	os.write_file(os.join_path(root, 'dst', 'a'), 'old')!

	src_fd := open_dir(os.join_path(root, 'src'))!
	dst_fd := open_dir(os.join_path(root, 'dst'))!
	defer {
		close(src_fd)
		close(dst_fd)
	}

	rename_noreplace(src_fd, 'a', dst_fd, 'a') or {
		assert is_exist(err)
		assert os.read_file(os.join_path(root, 'dst', 'a'))! == 'old'
		assert os.read_file(os.join_path(root, 'src', 'a'))! == 'new'
		return
	}
	assert false, 'rename must not replace an existing destination'
}

fn test_rename_noreplace_moves_when_free() {
	root := temp_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	os.mkdir_all(os.join_path(root, 'src'))!
	os.mkdir_all(os.join_path(root, 'dst'))!
	os.write_file(os.join_path(root, 'src', 'a'), 'payload')!

	src_fd := open_dir(os.join_path(root, 'src'))!
	dst_fd := open_dir(os.join_path(root, 'dst'))!
	defer {
		close(src_fd)
		close(dst_fd)
	}

	rename_noreplace(src_fd, 'a', dst_fd, 'a')!
	assert os.read_file(os.join_path(root, 'dst', 'a'))! == 'payload'
	assert !os.exists(os.join_path(root, 'src', 'a'))
}

fn test_mkdir_open_at_is_0700_and_reopens() {
	root := temp_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	root_fd := open_dir(root)!
	defer {
		close(root_fd)
	}

	fd := mkdir_open_at(root_fd, 'files', 0o700)!
	close(fd)

	again := mkdir_open_at(root_fd, 'files', 0o700)!
	close(again)

	info := os.lstat(os.join_path(root, 'files'))!
	assert info.mode & 0o777 == 0o700
}

fn test_canonical_path_of_an_open_directory() {
	root := temp_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	os.mkdir_all(os.join_path(root, 'sub'))!
	fd := open_dir(os.join_path(root, 'sub'))!
	defer {
		close(fd)
	}
	assert canonical_path(fd)! == os.real_path(os.join_path(root, 'sub'))
}

fn test_read_names_and_name_max() {
	root := temp_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	os.write_file(os.join_path(root, 'a'), '')!
	os.write_file(os.join_path(root, 'b'), '')!
	fd := open_dir(root)!
	defer {
		close(fd)
	}

	mut names := read_names(fd)!
	names.sort()
	assert names == ['a', 'b']
	assert !dir_is_empty(fd)!
	assert name_max(fd) > 0
}

fn test_dir_is_empty() {
	root := temp_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	fd := open_dir(root)!
	defer {
		close(fd)
	}
	assert dir_is_empty(fd)!
	os.write_file(os.join_path(root, 'a'), '')!
	assert !dir_is_empty(fd)!
}

fn test_unlink_at_removes_one_entry() {
	root := temp_root()!
	defer {
		os.rmdir_all(root) or {}
	}
	os.write_file(os.join_path(root, 'a'), '')!
	fd := open_dir(root)!
	defer {
		close(fd)
	}
	unlink_at(fd, 'a')!
	assert !os.exists(os.join_path(root, 'a'))
}
