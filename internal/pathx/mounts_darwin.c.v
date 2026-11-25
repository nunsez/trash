module pathx

#include <sys/mount.h>

// `struct statfs` and `getmntinfo` come from `<sys/mount.h>`; the declaration
// here only teaches V the field names. Only `f_mntonname` is read.
struct C.statfs {
	f_bsize       u32
	f_iosize      i32
	f_blocks      u64
	f_bfree       u64
	f_bavail      u64
	f_files       u64
	f_ffree       u64
	f_fsid        [2]i32
	f_owner       u32
	f_type        u32
	f_flags       u32
	f_fssubtype   u32
	f_fstypename  [16]char
	f_mntonname   [1024]char
	f_mntfromname [1024]char
	f_reserved    [8]u32
}

fn C.getmntinfo(mntbufp &&C.statfs, flags int) int

// system_mounts returns the mount points of the running kernel. The mount
// table is the source of truth for the mount guards.
pub fn system_mounts() ![]string {
	mut buf := &C.statfs(unsafe { nil })
	n := C.getmntinfo(&buf, C.MNT_NOWAIT)
	if n <= 0 {
		return error('getmntinfo failed')
	}
	mut points := []string{cap: n}
	for i in 0 .. n {
		points << unsafe { cstring_to_vstring(&buf[i].f_mntonname[0]) }
	}
	return points
}
