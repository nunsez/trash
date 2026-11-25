module windows

// This file is pure string handling for Windows path syntax. It has no
// Win32 dependency, so the rules can be tested without touching a filesystem.

// WinPath is a parsed Windows path.
pub struct WinPath {
pub:
	raw          string   // the path as the user wrote it
	absolute     bool     // starts with a drive or a UNC share
	unc          bool     // `\\server\share\...`
	root         string   // `C:\` or `\\server\share\`; '' when relative
	components   []string // the parts after the root, empty ones dropped
	trailing_sep bool     // the path ends with a separator
}

// parse splits a Windows path. Both `\` and `/` are separators.
pub fn parse(raw string) WinPath {
	normalized := raw.replace('/', '\\')
	if normalized.len == 0 {
		return WinPath{
			raw: raw
		}
	}
	mut root := ''
	mut rest := normalized
	mut unc := false
	if rest.starts_with('\\\\') {
		// `\\server\share` is the root; everything after it is relative to it.
		parts := rest[2..].split('\\')
		if parts.len >= 2 && parts[0] != '' && parts[1] != '' {
			unc = true
			root = '\\\\${parts[0]}\\${parts[1]}'
			rest = if parts.len > 2 { parts[2..].join('\\') } else { '' }
		}
	} else if rest.len >= 2 && is_drive_letter(rest[0]) && rest[1] == `:` {
		root = rest[..2] + '\\'
		rest = if rest.len > 2 { rest[2..].trim_left('\\') } else { '' }
	}
	mut components := []string{}
	for part in rest.split('\\') {
		if part != '' {
			components << part
		}
	}
	trailing_sep := normalized.len > root.len && normalized.ends_with('\\')
	return WinPath{
		raw:          raw
		absolute:     root != ''
		unc:          unc
		root:         root
		components:   components
		trailing_sep: trailing_sep
	}
}

fn is_drive_letter(c u8) bool {
	return (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`)
}

// name returns the last component, or '' for a root.
pub fn (p WinPath) name() string {
	if p.components.len == 0 {
		return ''
	}
	return p.components[p.components.len - 1]
}

// is_root reports whether the path names a volume root.
pub fn (p WinPath) is_root() bool {
	return p.absolute && p.components.len == 0
}

// absolute_path returns `p` with the current directory made explicit. The shell
// API resolves relative paths itself, but the quota check needs an absolute one.
pub fn absolute_path(raw string, cwd string) string {
	p := parse(raw)
	if p.absolute {
		return p.root + resolve_components([], p.components).join('\\')
	}
	base := parse(cwd)
	return base.root + resolve_components(base.components, p.components).join('\\')
}

// resolve_components applies `.` and `..` to `base` and then appends `components`.
fn resolve_components(base []string, components []string) []string {
	mut out := base.clone()
	for component in components {
		if component == '.' {
			continue
		}
		if component == '..' {
			if out.len > 0 {
				out.delete_last()
			}
			continue
		}
		out << component
	}
	return out
}

// resolved returns the components with `.` and `..` applied lexically, which is
// enough to compare a target with the current directory.
fn (p WinPath) resolved() []string {
	return resolve_components([], p.components)
}

// same_path compares two paths case-insensitively, ignoring `.`, `..` and
// repeated separators. Windows paths are not case sensitive.
pub fn same_path(a string, b string) bool {
	pa := parse(a)
	pb := parse(b)
	if pa.root.to_lower() != pb.root.to_lower() {
		return false
	}
	return pa.resolved().join('\\').to_lower() == pb.resolved().join('\\').to_lower()
}

// validate_path applies the Windows path rules. The returned errors carry the
// fixed refusal text, because this package cannot import `trash`.
//
// `cwd` is needed because the 259-character limit applies to the path the shell
// API actually sees, not to a short relative argument.
pub fn validate_path(raw string, cwd string) ! {
	p := parse(raw)
	abs := if p.absolute { raw } else { absolute_path(raw, cwd) }
	pa := parse(abs)
	if utf16_len(abs) > max_shell_path {
		return error('path too long for the Recycle Bin')
	}
	if pa.unc || p.unc {
		return error('no usable trash directory on this volume')
	}
	if pa.is_root() || is_only_separators(raw) {
		return error('refusing to trash a filesystem root')
	}
	for component in p.components {
		if component.contains(':') {
			return error('invalid path for the Recycle Bin')
		}
		if component.to_lower() == '$recycle.bin' {
			return error('refusing to trash the trash directory or one of its ancestors')
		}
		if is_reserved_name(component) {
			return error('invalid path for the Recycle Bin')
		}
	}
	name := p.name()
	if name == '' {
		return
	}
	if name.ends_with('.') || name.ends_with(' ') {
		return error('invalid path for the Recycle Bin')
	}
}

// is_only_separators reports whether `s` is a bare root such as `/`, `\` or
// `//`. Those have no components, so `parse` cannot tell them from a relative
// empty path.
fn is_only_separators(s string) bool {
	if s == '' {
		return false
	}
	for c in s {
		if c != `/` && c != `\\` {
			return false
		}
	}
	return true
}

// utf16_len counts UTF-16 code units, which is what the Windows path limit is
// expressed in; a rune above U+FFFF takes two.
fn utf16_len(s string) int {
	mut n := 0
	for r in s.runes() {
		n += if r > 0xFFFF { 2 } else { 1 }
	}
	return n
}

// max_shell_path is the longest path the shell API accepts (`MAX_PATH - 1`).
pub const max_shell_path = 259

// device_names returns the reserved device names. They are compared
// without an extension, because Windows treats `CON.txt` as the device too.
fn device_names() []string {
	return ['CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7',
		'COM8', 'COM9', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9']
}

// is_reserved_name reports whether a component names a device. Windows treats
// `CON.txt` as the device as well, so only the part before the first dot counts.
pub fn is_reserved_name(component string) bool {
	stem := component.split('.').first().to_upper()
	return stem in device_names()
}
