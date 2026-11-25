module trash

// PutOptions mirrors the flags of the CLI. The directory rules of the
// command line are applied by `put`, so a library caller gets the same
// refusals as the CLI.
//
// `@[params]` makes every field optional at the call site:
// `put(paths)` and `put(paths, force: true)` both work.
@[params]
pub struct PutOptions {
pub mut:
	force     bool // `-f`: ignore missing targets
	recursive bool // `-r`/`-R`: a real directory may be trashed
	dir       bool // `-d`/`--dir`: an empty directory may be trashed without `-r`
}

// PutResult is the outcome for one target. Failures are per item, matching
// `rm`'s continue-after-error semantics.
pub struct PutResult {
pub:
	path       string // target as given by the caller
	trashed    bool   // the object is in the trash
	trash_path string // absolute path inside the trash; '' when not trashed, always '' on Windows
	reason     string // human-readable failure reason; '' on success
}
