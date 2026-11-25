module trash

// put_one handles a single target. A missing target is silently skipped when
// `force` is set: the result then has neither `trashed` nor `reason`.
$if !windows {
	fn put_one(target string, opts PutOptions, mounts []string, mounts_ok bool) PutResult {
		trash_path := put_target(target, opts, mounts, mounts_ok) or {
			if opts.force && is_missing_error(err) {
				return PutResult{
					path: target
				}
			}
			return PutResult{
				path:   target
				reason: err.msg()
			}
		}
		return PutResult{
			path:       target
			trashed:    true
			trash_path: trash_path
		}
	}
}
