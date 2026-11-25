module trash

import internal.freedesktop

// nix_trash_candidates lists every trash directory that could serve the target,
// so the guard can refuse to trash a trash directory before anything is created.
fn nix_trash_candidates(dev u64, topdir string) []string {
	return freedesktop.candidate_paths(topdir, dev)
}

// nix_backend_put hands the resolved target to the freedesktop.org backend.
fn nix_backend_put(res Resolved, topdir string) !string {
	placed := freedesktop.put(freedesktop.Target{
		dir_fd: res.dir_fd
		name:   res.name
		st_dev: res.st.dev
		st_ino: res.st.ino
		topdir: topdir
	})!
	return placed.trash_path
}
