module freedesktop

import internal.fsx
import internal.pathx
import os
import time

// Target is one resolved target handed to the backend.
pub struct Target {
pub:
	dir_fd int    // directory holding the entry, walked with O_NOFOLLOW
	name   string // basename of the entry
	st_dev u64    // device of the entry
	st_ino u64    // inode of the entry, checked again right before the move
	topdir string // mount point of the volume that holds the entry
}

// Placed is where the object ended up.
pub struct Placed {
pub:
	trash_path string
}

// no_usable_trash is the refusal the CLI prints when no candidate works.
const no_usable_trash = 'no usable trash directory on this volume'

// max_attempts bounds the collision loop. A trash directory that already holds
// this many names for one basename is treated as unusable instead of spinning
// forever.
const max_attempts = 1000

// TrashDir is an opened and validated trash layout.
struct TrashDir {
	root_fd  int
	files_fd int
	info_fd  int
	root     string
}

// put moves one resolved target into the freedesktop.org trash of its volume.
pub fn put(target Target) !Placed {
	uid := u32(os.geteuid())
	td := open_trash(target.topdir, target.st_dev, uid) or {
		return error(no_usable_trash)
	}
	defer {
		fsx.close(td.root_fd)
		fsx.close(td.files_fd)
		fsx.close(td.info_fd)
	}
	return Placed{
		trash_path: place(target, td)!
	}
}

// place reserves a name, writes its metadata and then moves the payload, in
// that order: a payload without its metadata could never be restored.
fn place(target Target, td TrashDir) !string {
	parent := fsx.canonical_path(target.dir_fd)!
	abs := pathx.join(parent, target.name)
	content := trashinfo(relative_to(target.topdir, abs), time.now())
	limit := fsx.name_max(td.info_fd) - info_suffix.len
	mut attempt := 0
	for attempt < max_attempts {
		name := candidate_name(target.name, attempt, limit)
		info_name := name + info_suffix
		info_fd := fsx.create_excl_at(td.info_fd, info_name, 0o600) or {
			if fsx.is_exist(err) {
				attempt++
				continue
			}
			return err
		}
		fsx.write_all(info_fd, content) or {
			fsx.close(info_fd)
			discard_info(td, info_name)
			return err
		}
		fsx.sync(info_fd) or {
			fsx.close(info_fd)
			discard_info(td, info_name)
			return err
		}
		fsx.close(info_fd)
		// Re-check the entry immediately before the move: the guards saw this
		// exact inode, and anything else must not be moved under their name.
		st := fsx.stat_at(target.dir_fd, target.name) or {
			discard_info(td, info_name)
			return err
		}
		if st.dev != target.st_dev || st.ino != target.st_ino {
			discard_info(td, info_name)
			return error(fsx.target_changed)
		}
		fsx.rename_noreplace(target.dir_fd, target.name, td.files_fd, name) or {
			discard_info(td, info_name)
			if fsx.is_exist(err) {
				attempt++
				continue
			}
			return err
		}
		return pathx.join(pathx.join(td.root, 'files'), name)
	}
	return error('no name available in the trash directory')
}

// discard_info removes an info file that will never get its payload.
fn discard_info(td TrashDir, info_name string) {
	fsx.unlink_at(td.info_fd, info_name) or {}
}

// candidate_name appends the collision suffix and keeps the whole name within
// `NAME_MAX - len('.trashinfo')`.
fn candidate_name(base string, attempt int, limit int) string {
	if attempt == 0 {
		return shorten_name(base, limit)
	}
	return shorten_name('${base}.${attempt}', limit)
}

// relative_to strips the volume's top directory from a canonical path.
pub fn relative_to(topdir string, abs string) string {
	top := pathx.normalize(topdir)
	if top == '/' {
		return abs.trim_left('/')
	}
	if abs.starts_with(top + '/') {
		return abs[top.len + 1..]
	}
	return abs.trim_left('/')
}

// open_trash tries the candidates in order.
fn open_trash(topdir string, dev u64, uid u32) ?TrashDir {
	if td := try_home_trash(dev, uid) {
		return td
	}
	if td := try_shared_trash(topdir, dev, uid) {
		return td
	}
	if td := try_private_trash(topdir, dev, uid) {
		return td
	}
	return none
}

// try_home_trash is `$XDG_DATA_HOME/Trash`.
fn try_home_trash(dev u64, uid u32) ?TrashDir {
	home := xdg_data_home() or { return none }
	data_st := fsx.stat_path(home) or { return none }
	if !data_st.is_dir() || data_st.dev != dev {
		return none
	}
	root := pathx.join(home, 'Trash')
	root_fd := fsx.mkdir_open(root, 0o700) or { return none }
	if !valid_dir(root_fd, dev, uid) {
		fsx.close(root_fd)
		return none
	}
	return open_layout(root_fd, root, dev, uid)
}

// try_shared_trash is `$topdir/.Trash/$uid`, which only counts when the shared
// directory is real and sticky.
fn try_shared_trash(topdir string, dev u64, uid u32) ?TrashDir {
	shared := pathx.join(topdir, '.Trash')
	shared_st := fsx.stat_path(shared) or { return none }
	if !shared_st.is_dir() || shared_st.mode & 0o1000 == 0 {
		return none
	}
	root := pathx.join(shared, uid.str())
	root_st := fsx.stat_path(root) or { return none }
	if !root_st.is_dir() || root_st.uid != uid {
		return none
	}
	root_fd := fsx.open_dir(root) or { return none }
	if !valid_dir(root_fd, dev, uid) {
		fsx.close(root_fd)
		return none
	}
	return open_layout(root_fd, root, dev, uid)
}

// try_private_trash is `$topdir/.Trash-$uid`, created when it does not exist.
fn try_private_trash(topdir string, dev u64, uid u32) ?TrashDir {
	root := pathx.join(topdir, '.Trash-${uid}')
	root_fd := fsx.mkdir_open(root, 0o700) or { return none }
	if !valid_dir(root_fd, dev, uid) {
		fsx.close(root_fd)
		return none
	}
	return open_layout(root_fd, root, dev, uid)
}

// open_layout creates or opens `files/` and `info/` inside an accepted trash
// root and takes ownership of `root_fd`.
fn open_layout(root_fd int, root string, dev u64, uid u32) ?TrashDir {
	files_fd := fsx.mkdir_open_at(root_fd, 'files', 0o700) or {
		fsx.close(root_fd)
		return none
	}
	if !valid_dir(files_fd, dev, uid) {
		fsx.close(root_fd)
		fsx.close(files_fd)
		return none
	}
	info_fd := fsx.mkdir_open_at(root_fd, 'info', 0o700) or {
		fsx.close(root_fd)
		fsx.close(files_fd)
		return none
	}
	if !valid_dir(info_fd, dev, uid) {
		fsx.close(root_fd)
		fsx.close(files_fd)
		fsx.close(info_fd)
		return none
	}
	return TrashDir{
		root_fd:  root_fd
		files_fd: files_fd
		info_fd:  info_fd
		root:     root
	}
}

// valid_dir reports whether an open directory is a real directory, owned by the
// effective uid, on the source's device.
fn valid_dir(fd int, dev u64, uid u32) bool {
	st := fsx.stat_fd(fd) or { return false }
	return st.is_dir() && st.dev == dev && st.uid == uid
}
