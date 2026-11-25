module fsx

// Descriptor-relative filesystem primitives for Unix. Everything the
// library does to a path goes through these calls, so that a guard and the move
// it authorises cannot be separated by a swapped path component.

import os

#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

$if linux {
	#include <sys/syscall.h>
}

struct C.stat {
	st_dev  u64
	st_ino  u64
	st_mode u32
	st_uid  u32
	st_size u64
}

struct C.dirent {
	d_ino     u64
	d_seekoff u64
	d_reclen  u16
	d_namlen  u16
	d_type    u8
	d_name    [256]char
}

fn C.openat(dirfd int, path &char, flags int, ...) int
fn C.close(fd int) int
fn C.fstat(fd int, buf &C.stat) int
fn C.fstatat(dirfd int, path &char, buf &C.stat, flags int) int
fn C.mkdirat(dirfd int, path &char, mode u32) int
fn C.unlinkat(dirfd int, path &char, flags int) int
fn C.fchmod(fd int, mode u32) int
fn C.fsync(fd int) int
fn C.write(fd int, buf voidptr, count uint) int
fn C.renameat(olddirfd int, oldpath &char, newdirfd int, newpath &char) int
fn C.fpathconf(fd int, name int) i64
fn C.fdopendir(fd int) voidptr
fn C.readdir(dirp voidptr) &C.dirent
fn C.closedir(dirp voidptr) int
fn C.fcntl(fd int, cmd int, ...) int

$if linux {
	fn C.syscall(number int, ...) int
} $else {
	fn C.renameatx_np(fromfd int, from &char, tofd int, to &char, flags u32) int
}

// rename_noreplace_flag is RENAME_NOREPLACE from `<linux/fs.h>`.
const rename_noreplace_flag = 1

const max_path = 1024

// errno_error turns the current errno into a V error that keeps the code.
fn errno_error() IError {
	code := C.errno
	return error_with_code(os.posix_get_error_msg(code), code)
}

// is_exist reports whether the failure means "the name is already taken".
pub fn is_exist(err IError) bool {
	return err.code() == C.EEXIST
}

// is_missing reports whether the failure means "no such entry".
pub fn is_missing(err IError) bool {
	return err.code() == C.ENOENT
}

// is_loop reports whether the failure was caused by a symlink in the path.
pub fn is_loop(err IError) bool {
	return err.code() == C.ELOOP
}

// is_not_dir reports whether the failure means "a path component is not a
// directory".
pub fn is_not_dir(err IError) bool {
	return err.code() == C.ENOTDIR
}

// open_dir_at opens `name` inside `dir_fd` as a directory, never following a
// symlink. The caller closes the returned descriptor.
pub fn open_dir_at(dir_fd int, name string) !int {
	return open_at(dir_fd, name, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
}

// open_dir opens a directory by path. Only the last component is protected
// against symlinks: this is used for trash directories, whose location comes
// from the environment, not from the user's argument.
pub fn open_dir(path string) !int {
	return open_at(at_fdcwd(), path, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC,
		0)
}

// create_excl_at creates `name` inside `dir_fd` and returns an open descriptor.
// `O_EXCL` both reserves the name against a concurrent run and refuses a
// pre-planted symlink.
pub fn create_excl_at(dir_fd int, name string, mode int) !int {
	return open_at(dir_fd, name, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW |
		C.O_CLOEXEC, mode)
}

// mkdir_open_at creates `name` inside `dir_fd` with `mode`, opens it and applies
// `mode` again with `fchmod`, so the umask cannot change the result. `EEXIST` is
// not an error here: the existing directory is opened and only validated, never
// re-`chmod`ed.
pub fn mkdir_open_at(dir_fd int, name string, mode int) !int {
	mut created := true
	mkdir_at(dir_fd, name, mode) or {
		if !is_exist(err) {
			return err
		}
		created = false
	}
	fd := open_dir_at(dir_fd, name)!
	if created && C.fchmod(fd, u32(mode)) != 0 {
		err := errno_error()
		C.close(fd)
		return err
	}
	return fd
}

// real_path resolves every symlink and `.`/`..` in `path` with `realpath(3)`.
// The caller uses it on the parent directory only, because the final component
// must not be resolved.
pub fn real_path(path string) !string {
	resolved := C.realpath(path.str, 0)
	if isnil(resolved) {
		return errno_error()
	}
	defer {
		C.free(resolved)
	}
	return unsafe { cstring_to_vstring(resolved) }
}

// mkdir_open creates a directory by path (an existing one is opened, not
// replaced), applies `mode` with `fchmod` and returns the descriptor.
pub fn mkdir_open(path string, mode int) !int {
	return mkdir_open_at(at_fdcwd(), path, mode)
}

// mkdir_at creates one directory inside `dir_fd`.
pub fn mkdir_at(dir_fd int, name string, mode int) ! {
	if C.mkdirat(dir_fd, name.str, u32(mode)) != 0 {
		return errno_error()
	}
}

fn open_at(dir_fd int, path string, flags int, mode int) !int {
	fd := C.openat(dir_fd, path.str, flags, u32(mode))
	if fd < 0 {
		return errno_error()
	}
	return fd
}

// stat_at describes `name` inside `dir_fd` without following a symlink.
pub fn stat_at(dir_fd int, name string) !Stat {
	mut st := C.stat{}
	if C.fstatat(dir_fd, name.str, &st, C.AT_SYMLINK_NOFOLLOW) != 0 {
		return errno_error()
	}
	return to_stat(&st)
}

// stat_path describes a path without following a symlink. It is used for the
// trash directories, whose location comes from the environment rather than from
// the user's argument.
pub fn stat_path(path string) !Stat {
	return stat_at(at_fdcwd(), path)
}

// stat_cwd describes the current working directory.
pub fn stat_cwd() !Stat {
	return stat_at(at_fdcwd(), '.')
}

// stat_fd describes an open descriptor.
pub fn stat_fd(fd int) !Stat {
	mut st := C.stat{}
	if C.fstat(fd, &st) != 0 {
		return errno_error()
	}
	return to_stat(&st)
}

fn to_stat(st &C.stat) Stat {
	return Stat{
		dev:  u64(st.st_dev)
		ino:  u64(st.st_ino)
		mode: u32(st.st_mode)
		uid:  u32(st.st_uid)
		size: u64(st.st_size)
	}
}

// rename_noreplace moves an entry without ever replacing an existing one. The
// fallback for a kernel without the atomic call is a `fstatat` followed by
// `renameat`, which loses the guarantee for the duration of that window; it only
// runs where the atomic call is not implemented.
pub fn rename_noreplace(src_dir_fd int, src_name string, dst_dir_fd int, dst_name string) ! {
	$if linux {
		// `renameat2` is only declared by glibc under `_GNU_SOURCE`, which the
		// generated C does not define, so the raw syscall is used instead.
		if C.syscall(C.SYS_renameat2, src_dir_fd, src_name.str, dst_dir_fd, dst_name.str,
			rename_noreplace_flag) == 0 {
			return
		}
		err := errno_error()
		if err.code() != C.ENOSYS && err.code() != C.EINVAL {
			return err
		}
	} $else {
		if C.renameatx_np(src_dir_fd, src_name.str, dst_dir_fd, dst_name.str, u32(C.RENAME_EXCL)) == 0 {
			return
		}
		err := errno_error()
		if err.code() != C.ENOTSUP && err.code() != C.EINVAL {
			return err
		}
	}
	stat_at(dst_dir_fd, dst_name) or {
		if is_missing(err) {
			return rename_at(src_dir_fd, src_name, dst_dir_fd, dst_name)
		}
		return err
	}
	return error_with_code(os.posix_get_error_msg(C.EEXIST), C.EEXIST)
}

fn rename_at(src_dir_fd int, src_name string, dst_dir_fd int, dst_name string) ! {
	// `renameat` is declared in <stdio.h>, which the generated C does not
	// include; the raw syscall needs only <sys/syscall.h>.
	$if linux {
		if C.syscall(C.SYS_renameat, src_dir_fd, src_name.str, dst_dir_fd, dst_name.str) != 0 {
			return errno_error()
		}
	} $else {
		if C.renameat(src_dir_fd, src_name.str, dst_dir_fd, dst_name.str) != 0 {
			return errno_error()
		}
	}
}

// unlink_at removes one entry inside `dir_fd`.
pub fn unlink_at(dir_fd int, name string) ! {
	if C.unlinkat(dir_fd, name.str, 0) != 0 {
		return errno_error()
	}
}

// write_all writes the whole buffer to an open descriptor.
pub fn write_all(fd int, data string) ! {
	mut written := 0
	for written < data.len {
		n := C.write(fd, unsafe { voidptr(data.str + written) }, uint(data.len - written))
		if n < 0 {
			if C.errno == C.EINTR {
				continue
			}
			return errno_error()
		}
		if n == 0 {
			return error('short write')
		}
		written += int(n)
	}
}

// sync flushes an open descriptor to the device.
pub fn sync(fd int) ! {
	if C.fsync(fd) != 0 {
		return errno_error()
	}
}

// close closes a descriptor and ignores the result.
pub fn close(fd int) {
	if fd >= 0 {
		C.close(fd)
	}
}

// canonical_path returns the absolute, symlink-free path of an open
// descriptor. The descriptor must stay open while the result is used.
pub fn canonical_path(fd int) !string {
	$if linux {
		return os.readlink('/proc/self/fd/${fd}')
	} $else {
		mut buf := [max_path]char{}
		if C.fcntl(fd, C.F_GETPATH, &buf[0]) < 0 {
			return errno_error()
		}
		return unsafe { cstring_to_vstring(&buf[0]) }
	}
}

// name_max returns the longest file name the filesystem behind `dir_fd`
// accepts, with a 255 fallback.
pub fn name_max(dir_fd int) int {
	n := C.fpathconf(dir_fd, C._PC_NAME_MAX)
	if n <= 0 {
		return 255
	}
	return int(n)
}

// dir_is_empty reports whether an open directory holds no entries besides `.`
// and `..`. It stops at the first real entry, so a huge directory costs one
// `readdir` call instead of a full listing. It opens a fresh descriptor for the
// directory, so the caller keeps ownership of `dir_fd` and its offset is not
// disturbed.
pub fn dir_is_empty(dir_fd int) !bool {
	fd := open_at(dir_fd, '.', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC, 0)!
	dir := C.fdopendir(fd)
	if isnil(dir) {
		err := errno_error()
		C.close(fd)
		return err
	}
	for {
		C.errno = 0
		ent := C.readdir(dir)
		if isnil(ent) {
			if C.errno != 0 {
				err := errno_error()
				C.closedir(dir)
				return err
			}
			break
		}
		name := unsafe { cstring_to_vstring(&ent.d_name[0]) }
		if name == '.' || name == '..' {
			continue
		}
		C.closedir(dir)
		return false
	}
	C.closedir(dir)
	return true
}

// read_names returns every entry of an open directory except `.` and `..`. It
// opens a fresh descriptor for the directory, so the caller keeps ownership of
// `dir_fd` and its offset is not disturbed.
pub fn read_names(dir_fd int) ![]string {
	fd := open_at(dir_fd, '.', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC, 0)!
	dir := C.fdopendir(fd)
	if isnil(dir) {
		err := errno_error()
		C.close(fd)
		return err
	}
	mut names := []string{}
	for {
		// `readdir` returns NULL both at the end of the directory and on error;
		// clearing errno first is the only portable way to tell them apart.
		C.errno = 0
		ent := C.readdir(dir)
		if isnil(ent) {
			if C.errno != 0 {
				err := errno_error()
				C.closedir(dir)
				return err
			}
			break
		}
		name := unsafe { cstring_to_vstring(&ent.d_name[0]) }
		if name == '.' || name == '..' {
			continue
		}
		names << name
	}
	C.closedir(dir)
	return names
}

// at_fdcwd is the pseudo descriptor that makes a call use the working
// directory.
fn at_fdcwd() int {
	$if linux {
		return -100
	} $else {
		return -2
	}
}
