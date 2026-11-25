module trash

import internal.darwin
import internal.fsx
import internal.pathx
import os

// nix_trash_candidates lists the trash locations macOS uses: `~/.Trash` on the
// boot volume and `/.Trashes/<uid>` on every other volume.
fn nix_trash_candidates(_dev u64, topdir string) []string {
	mut paths := []string{}
	home := os.getenv('HOME')
	if home != '' && os.is_abs_path(home) {
		// The guard compares this against a canonical target path, so a symlinked
		// or firmlinked home must be resolved first.
		resolved := fsx.real_path(home) or { pathx.normalize(home) }
		paths << pathx.join(resolved, '.Trash')
	}
	paths << pathx.join(topdir, '.Trashes/${os.geteuid()}')
	return paths
}

// nix_backend_put hands the resolved target to the NSFileManager backend.
fn nix_backend_put(res Resolved, _topdir string) !string {
	placed := darwin.put(darwin.Target{
		dir_fd: res.dir_fd
		name:   res.name
		st_dev: res.st.dev
		st_ino: res.st.ino
	})!
	return placed.trash_path
}
