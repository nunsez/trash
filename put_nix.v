module trash

import internal.fsx
import internal.pathx

fn put_impl(targets []string, opts PutOptions) []PutResult {
	return put_many(targets, opts)
}

// Resolved is a target after the descriptor walk: the descriptor of the
// directory that holds it, its basename, its identity from `fstatat`, and the
// canonical path built from the parent descriptor.
struct Resolved {
	dir_fd int
	name   string
	st     fsx.Stat
	path   string // canonical absolute path
}

// GuardContext carries what the guards need and the filesystem cannot answer:
// the mount table and the trash directories that could be used for the target's
// volume.
@[params]
struct GuardContext {
	mounts     []string
	candidates []string
}

// put_one handles a single target. A missing target is silently skipped when
// `force` is set: the result then has neither `trashed` nor `reason`.
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

// put_many is the Unix batch entry point. The mount table is read and
// normalized once for the whole command line, not once per target.
fn put_many(targets []string, opts PutOptions) []PutResult {
	mut mounts_ok := true
	mounts := pathx.system_mounts() or {
		mounts_ok = false
		[]string{}
	}
	if mounts.len == 0 {
		mounts_ok = false
	}
	mut normalized := []string{cap: mounts.len}
	for m in mounts {
		normalized << pathx.normalize(m)
	}
	mut results := []PutResult{cap: targets.len}
	for target in targets {
		results << put_one(target, opts, normalized, mounts_ok)
	}
	return results
}

// put_target is the Unix path of `put`: guards, then the platform backend.
fn put_target(target string, opts PutOptions, mounts []string, mounts_ok bool) !string {
	p := pathx.parse(target)
	if p.is_root() {
		return TrashError{ kind: .root }
	}
	if p.name() == '.' || p.name() == '..' {
		return TrashError{ kind: .dot_dot }
	}
	res := resolve_target(target)!
	defer {
		fsx.close(res.dir_fd)
	}
	if !mounts_ok {
		return TrashError{ kind: .mount_table }
	}
	topdir := pathx.topdir(res.path, mounts)
	ctx := GuardContext{
		mounts:     mounts
		candidates: nix_trash_candidates(res.st.dev, topdir)
	}
	check_guards(res, p, opts, ctx)!
	return nix_backend_put(res, topdir)
}

// resolve_target resolves the parent of the argument with `realpath(3)` and then
// walks the resolved path one component at a time with `O_NOFOLLOW`, describing
// the final entry without opening it. This is what makes `trash /tmp/x`
// behave like `rm /tmp/x` where `/tmp` is a symlink, while a component swapped
// after the resolution still fails the walk.
fn resolve_target(arg string) !Resolved {
	p := pathx.parse(arg)
	parent := fsx.real_path(p.parent_arg())!
	mut fd := fsx.open_dir('/')!
	for dir in pathx.parse(parent).components {
		next := fsx.open_dir_at(fd, dir) or {
			fsx.close(fd)
			return err
		}
		fsx.close(fd)
		fd = next
	}
	name := p.name()
	st := fsx.stat_at(fd, name) or {
		fsx.close(fd)
		return err
	}
	canonical := fsx.canonical_path(fd) or {
		fsx.close(fd)
		return err
	}
	return Resolved{
		dir_fd: fd
		name:   name
		st:     st
		path:   pathx.join(canonical, name)
	}
}

// check_guards applies the guards and the directory rules. Every guard is
// evaluated before a trash directory is created or opened.
fn check_guards(res Resolved, p pathx.Path, opts PutOptions, ctx GuardContext) !void {
	if p.trailing_sep && !res.st.is_dir() {
		return TrashError{ kind: .not_a_directory }
	}
	if res.st.is_dir() && !opts.recursive {
		if !opts.dir {
			return TrashError{ kind: .needs_recursive }
		}
		if !dir_is_empty(res) {
			return TrashError{ kind: .dir_not_empty }
		}
	}
	if is_current_dir(res.st) {
		return TrashError{ kind: .current_dir }
	}
	if pathx.is_mount_point(res.path, ctx.mounts) {
		return TrashError{ kind: .mount_point }
	}
	if res.st.is_dir() && pathx.contains_mount_point(res.path, ctx.mounts) {
		return TrashError{ kind: .contains_mount }
	}
	for candidate in ctx.candidates {
		if pathx.covers(res.path, candidate) {
			return TrashError{ kind: .trash_dir }
		}
	}
}

// dir_is_empty reports whether the directory holds no entries besides `.` and
// `..`. A directory that cannot be read is reported as non-empty, so the target
// is refused instead of moved.
fn dir_is_empty(res Resolved) bool {
	fd := fsx.open_dir_at(res.dir_fd, res.name) or { return false }
	defer {
		fsx.close(fd)
	}
	return fsx.dir_is_empty(fd) or { false }
}

// is_current_dir reports whether the entry is the working directory itself.
fn is_current_dir(st fsx.Stat) bool {
	cwd := fsx.stat_cwd() or { return false }
	return cwd.dev == st.dev && cwd.ino == st.ino
}
