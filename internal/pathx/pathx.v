module pathx

// Path is an argument split into the pieces the descriptor walk needs.
// Empty components are dropped, `.` and `..` are kept so that the caller can
// decide what to do with them.
pub struct Path {
pub:
	absolute     bool
	trailing_sep bool // the argument ended with '/'
	components   []string
}

// parse splits a target argument. It never touches the filesystem.
pub fn parse(arg string) Path {
	mut components := []string{}
	for part in arg.split('/') {
		if part == '' {
			continue
		}
		components << part
	}
	return Path{
		absolute:     arg.starts_with('/')
		trailing_sep: arg.len > 1 && arg.ends_with('/')
		components:   components
	}
}

// name returns the last component, or '' when there is none.
pub fn (p Path) name() string {
	if p.components.len == 0 {
		return ''
	}
	return p.components[p.components.len - 1]
}

// dirs returns every component except the last one.
pub fn (p Path) dirs() []string {
	if p.components.len == 0 {
		return []
	}
	return p.components[..p.components.len - 1]
}

// parent_arg rebuilds the argument without its last component, which is what
// `realpath` is applied to. A bare name resolves against `.`.
pub fn (p Path) parent_arg() string {
	dirs := p.dirs()
	if dirs.len == 0 {
		return if p.absolute { '/' } else { '.' }
	}
	joined := dirs.join('/')
	return if p.absolute { '/' + joined } else { joined }
}

// is_root reports whether the path is a filesystem root (`/`, `//`).
pub fn (p Path) is_root() bool {
	return p.absolute && p.components.len == 0
}

// join appends one component to a canonical directory path.
pub fn join(dir string, name string) string {
	if dir == '/' {
		return '/' + name
	}
	return dir + '/' + name
}

// normalize strips trailing separators, keeping `/` as it is. Mount table
// entries and canonical paths are compared after this.
pub fn normalize(path string) string {
	mut p := path
	for p.len > 1 && p.ends_with('/') {
		p = p[..p.len - 1]
	}
	return p
}

// covers reports whether `ancestor` is `path` itself or one of its ancestors.
// Both arguments must be canonical absolute paths.
pub fn covers(ancestor string, path string) bool {
	if ancestor == '/' {
		return path.starts_with('/')
	}
	return path == ancestor || path.starts_with(ancestor + '/')
}

// is_mount_point reports whether `path` is a mount point of `mounts`.
// `mounts` must already be normalized (see `normalize`).
pub fn is_mount_point(path string, mounts []string) bool {
	p := normalize(path)
	for m in mounts {
		if m == p {
			return true
		}
	}
	return false
}

// contains_mount_point reports whether any mount point lies strictly below
// `dir`. Both arguments must be canonical absolute paths; `mounts` must already
// be normalized.
pub fn contains_mount_point(dir string, mounts []string) bool {
	d := normalize(dir)
	for m in mounts {
		if m == d {
			continue
		}
		if covers(d, m) {
			return true
		}
	}
	return false
}

// topdir returns the mount point of the volume that holds `path`, the longest
// matching entry of the mount table. `/` is the fallback. `mounts` must already
// be normalized.
pub fn topdir(path string, mounts []string) string {
	p := normalize(path)
	mut best := '/'
	for m in mounts {
		if covers(m, p) && m.len > best.len {
			best = m
		}
	}
	return best
}

// decode_escapes decodes the octal escapes of a `/proc/self/mountinfo` field
// (`\040`, `\011`, `\012`, `\134`) into the bytes they stand for.
pub fn decode_escapes(field string) string {
	mut out := []u8{cap: field.len}
	mut i := 0
	for i < field.len {
		c := field[i]
		if c == `\\` && i + 3 < field.len {
			b, ok := octal_byte(field[i + 1..i + 4])
			if ok {
				out << b
				i += 4
				continue
			}
		}
		out << c
		i++
	}
	return out.bytestr()
}

fn octal_byte(digits string) (u8, bool) {
	if digits.len != 3 {
		return 0, false
	}
	mut value := 0
	for d in digits {
		if d < `0` || d > `7` {
			return 0, false
		}
		value = value * 8 + int(d - `0`)
	}
	if value > 255 {
		return 0, false
	}
	return u8(value), true
}

// parse_mountinfo extracts the mount points of a Linux `/proc/self/mountinfo`
// file. The mount point is the fifth field; the file escapes spaces, tabs,
// newlines and backslashes as octal sequences.
pub fn parse_mountinfo(text string) []string {
	mut points := []string{}
	for line in text.split_into_lines() {
		if line == '' {
			continue
		}
		fields := line.split(' ')
		if fields.len < 5 {
			continue
		}
		points << decode_escapes(fields[4])
	}
	return points
}
