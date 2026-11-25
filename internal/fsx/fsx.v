module fsx

// target_changed is the reason a backend reports when the entry it was asked
// to move is no longer the entry the guards approved. It is a fixed, composed
// reason, like the ones in the `trash` package.
pub const target_changed = 'the target changed during the operation'

// Stat is the subset of `struct stat` the guards and the backends need.
pub struct Stat {
pub:
	dev  u64 // device that holds the entry
	ino  u64 // inode number
	mode u32 // file type and permission bits
	uid  u32 // owner
	size u64 // size in bytes
}

const ifmt = 0o170000
const ifdir = 0o040000
const ifreg = 0o100000
const iflnk = 0o120000

// is_dir reports whether the entry is a directory.
pub fn (s Stat) is_dir() bool {
	return (s.mode & ifmt) == ifdir
}

// is_file reports whether the entry is a regular file.
pub fn (s Stat) is_file() bool {
	return (s.mode & ifmt) == ifreg
}

// is_link reports whether the entry is a symlink.
pub fn (s Stat) is_link() bool {
	return (s.mode & ifmt) == iflnk
}
