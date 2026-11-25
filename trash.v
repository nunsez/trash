module trash

// put moves every target into the system trash and reports the outcome per
// item. It never deletes anything and never returns an error type.
pub fn put(targets []string, opts PutOptions) []PutResult {
	$if windows {
		// `IFileOperation` is a batch operation, so the whole command line is
		// handed to the backend at once.
		return put_all(targets, opts)
	} $else {
		return put_many(targets, opts)
	}
}
