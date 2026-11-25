module trash

import internal.windows
import os

// On Windows the shell API resolves paths itself, so the descriptor walk has no
// equivalent: the guards here work on the path string and on the attributes of
// the object.

// put_all handles the whole command line at once, because `IFileOperation` is a
// batch operation: one `PerformOperations` covers every accepted target.
fn put_all(targets []string, opts PutOptions) []PutResult {
	mut reasons := []string{len: targets.len}
	mut skipped := []bool{len: targets.len}
	mut accepted := []int{cap: targets.len}
	cwd := os.getwd()
	for i, target in targets {
		// Path syntax is checked before `-f`: a missing target with an invalid
		// path is still an error, and `-f` only silences "does not exist".
		mut reason := windows_static_reason(target, cwd)
		if reason != '' {
			reasons[i] = reason
			continue
		}
		if opts.force && windows.is_missing(target) {
			skipped[i] = true
			continue
		}
		reason = windows_target_reason(target, opts, cwd)
		if reason != '' {
			reasons[i] = reason
			continue
		}
		accepted << i
	}
	if accepted.len > 0 {
		// The quota is checked against the total size of the batch per volume,
		// not per item: `IFileOperation` moves the whole batch, and an item that
		// does not fit is deleted permanently instead of recycled (`D19`).
		mut paths := []string{len: targets.len}
		mut roots := []string{len: targets.len}
		mut totals := map[string]u64{}
		mut batch := []int{cap: accepted.len}
		for i in accepted {
			abs := windows.absolute_path(targets[i], cwd)
			size := windows.path_size(abs) or {
				reasons[i] = err.msg()
				continue
			}
			root := windows.volume_root(abs) or {
				reasons[i] = err.msg()
				continue
			}
			paths[i] = abs
			roots[i] = root
			totals[root] = (totals[root] or { u64(0) }) + size
			batch << i
		}
		mut final := []int{cap: batch.len}
		for i in batch {
			windows.quota_allows(paths[i], totals[roots[i]]) or {
				reasons[i] = err.msg()
				continue
			}
			final << i
		}
		if final.len > 0 {
			mut place_paths := []string{cap: final.len}
			for i in final {
				place_paths << paths[i]
			}
			placed := windows.place(place_paths)
			for k, i in final {
				reasons[i] = placed[k]
			}
		}
	}
	return windows_results(targets, reasons, skipped)
}

// windows_static_reason applies the path rules that need no filesystem access
// and returns the reason of the first refusal, or '' when the path is usable.
fn windows_static_reason(target string, cwd string) string {
	p := windows.parse(target)
	name := p.name()
	if name == '.' || name == '..' {
		return TrashError{ kind: .dot_dot }.msg()
	}
	windows.validate_path(target, cwd) or { return err.msg() }
	return ''
}

// windows_target_reason applies the guards that inspect the object itself and
// returns the reason of the first refusal, or '' when it may be trashed.
fn windows_target_reason(target string, opts PutOptions, cwd string) string {
	check_windows_target(target, opts, cwd) or { return err.msg() }
	return ''
}

fn check_windows_target(target string, opts PutOptions, cwd string) ! {
	p := windows.parse(target)
	abs := windows.absolute_path(target, cwd)
	attributes := windows.attributes(abs)!
	is_reparse := attributes & windows.attr_reparse_point != 0
	// A junction or symlink is trashed as a link (`D26`), so it never counts as
	// a directory and never needs `-r`, even though `GetFileAttributesW`
	// reports the directory bit of the target.
	is_dir := (attributes & windows.attr_directory) != 0 && !is_reparse
	if p.trailing_sep && !is_dir {
		return TrashError{ kind: .not_a_directory }
	}
	if is_reparse {
		if windows.is_volume_root_junction(abs)! {
			return TrashError{ kind: .mount_point }
		}
	} else if is_dir {
		if !opts.recursive && !opts.dir {
			return TrashError{ kind: .needs_recursive }
		}
		if opts.dir && !opts.recursive && !windows.is_empty_dir(abs) {
			return TrashError{ kind: .dir_not_empty }
		}
	}
	if windows.same_path(target, cwd) {
		return TrashError{ kind: .current_dir }
	}
}

// windows_results builds one result per target, in the order of the command line.
fn windows_results(targets []string, reasons []string, skipped []bool) []PutResult {
	mut results := []PutResult{cap: targets.len}
	for i, target in targets {
		if skipped[i] {
			results << PutResult{
				path: target
			}
			continue
		}
		if reasons[i] != '' {
			results << PutResult{
				path:   target
				reason: reasons[i]
			}
			continue
		}
		results << PutResult{
			path:    target
			trashed: true
		}
	}
	return results
}
