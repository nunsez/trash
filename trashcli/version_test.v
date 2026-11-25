module trashcli

import os
import v.vmod

// version must stay equal to `v.mod`: the manifest is what a package
// consumer reads, and `--version` is what a user reads.
fn test_version_matches_v_mod() {
	manifest := vmod.decode(os.read_file('${@VMODROOT}/v.mod')!)!
	assert manifest.version == version
}
