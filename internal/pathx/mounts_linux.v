module pathx

import os

// system_mounts returns the mount points of the running kernel. The mount
// table is the source of truth for the mount guards.
pub fn system_mounts() ![]string {
	text := os.read_file('/proc/self/mountinfo')!
	return parse_mountinfo(text)
}
