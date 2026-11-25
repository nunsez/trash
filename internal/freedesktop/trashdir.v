module freedesktop

import internal.fsx
import internal.pathx
import os

// xdg_data_home returns `$XDG_DATA_HOME`, or `$HOME/.local/share` when the
// variable is unset. A relative value is ignored.
pub fn xdg_data_home() ?string {
	xdg := os.getenv('XDG_DATA_HOME')
	if xdg != '' {
		if os.is_abs_path(xdg) {
			return pathx.normalize(xdg)
		}
		return none
	}
	home := os.getenv('HOME')
	if home == '' || !os.is_abs_path(home) {
		return none
	}
	return pathx.join(pathx.normalize(home), '.local/share')
}

// candidate_paths returns every trash directory that could serve a target on
// the volume mounted at `topdir`, in priority order. It is read-only:
// nothing is created and nothing is validated beyond "this location is on the
// target's volume".
pub fn candidate_paths(topdir string, target_dev u64) []string {
	mut paths := []string{}
	if home_trash := home_trash_path(target_dev) {
		paths << home_trash
	}
	uid := os.geteuid()
	paths << pathx.join(pathx.join(topdir, '.Trash'), uid.str())
	paths << pathx.join(topdir, '.Trash-${uid}')
	return paths
}

// home_trash_path is `$XDG_DATA_HOME/Trash`, but only when the data directory
// already exists and lies on the target's volume.
fn home_trash_path(target_dev u64) ?string {
	data_home := xdg_data_home() or { return none }
	data_st := fsx.stat_path(data_home) or { return none }
	if !data_st.is_dir() || data_st.dev != target_dev {
		return none
	}
	return pathx.join(data_home, 'Trash')
}
