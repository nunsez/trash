module pathx

// system_mounts has no Windows counterpart: a mount point there is a reparse
// point, which the Windows backend detects on its own, so the mount guards
// never need a mount table.
pub fn system_mounts() ![]string {
	return []
}
