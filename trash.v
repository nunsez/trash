module trash

// put moves every target into the system trash and reports the outcome per
// item. It never deletes anything and never returns an error type.
pub fn put(targets []string, opts PutOptions) []PutResult {
	return put_impl(targets, opts)
}
