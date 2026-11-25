module pathx

// Unix-only: Windows has no mount table; its mount points are reparse points
// handled by the backend.
fn test_system_mounts_are_absolute() {
	mounts := system_mounts() or { return }
	assert mounts.len > 0
	for m in mounts {
		assert m.starts_with('/')
	}
}
