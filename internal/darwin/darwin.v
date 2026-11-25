module darwin

import internal.fsx
import internal.pathx

// Target is one resolved target handed to the backend.
pub struct Target {
pub:
	dir_fd int    // directory holding the entry, walked with O_NOFOLLOW
	name   string // basename of the entry
	st_dev u64    // device of the entry
	st_ino u64    // inode of the entry, checked again right before the move
}

// Placed is where the object ended up, as reported by the system.
pub struct Placed {
pub:
	trash_path string
}

// put moves one resolved target into the trash of its volume with
// `NSFileManager trashItemAtURL:`. A failure is the error for that target:
// there is no fallback and nothing is ever deleted permanently.
pub fn put(target Target) !Placed {
	st := fsx.stat_at(target.dir_fd, target.name)!
	if st.dev != target.st_dev || st.ino != target.st_ino {
		return error(fsx.target_changed)
	}
	parent := fsx.canonical_path(target.dir_fd)!
	return Placed{
		trash_path: trash_item(pathx.join(parent, target.name))!
	}
}
