module freedesktop

import time

// info_suffix is appended to every payload name to form the info file name.
const info_suffix = '.trashinfo'

// encode_path percent-encodes one path for the `Path` key of a `.trashinfo`.
// The bytes of `A-Za-z0-9-_.~/` stay literal, everything else becomes `%XX`
// with uppercase hex digits.
pub fn encode_path(path string) string {
	mut out := []u8{cap: path.len}
	for b in path {
		if (b >= `A` && b <= `Z`) || (b >= `a` && b <= `z`) || (b >= `0` && b <= `9`)
			|| b == `-` || b == `_` || b == `.` || b == `~` || b == `/` {
			out << b
		} else {
			out << `%`
			out << hex_digit(b >> 4)
			out << hex_digit(b & 0x0f)
		}
	}
	return out.bytestr()
}

fn hex_digit(value u8) u8 {
	if value < 10 {
		return `0` + value
	}
	return `A` + (value - 10)
}

// trashinfo returns the exact content of the info file for a payload that was
// at `rel` — relative to the volume's top directory — at `t`.
pub fn trashinfo(rel string, t time.Time) string {
	date := t.format_ss().replace(' ', 'T')
	return '[Trash Info]\nPath=${encode_path(rel)}\nDeletionDate=${date}\n'
}

// shorten_name shortens `name` so that `name.len` fits `limit`, keeping the
// extension when it fits. Truncation happens on a UTF-8 boundary.
pub fn shorten_name(name string, limit int) string {
	if name.len <= limit || limit <= 0 {
		return name
	}
	dot := name.last_index('.') or { -1 }
	// Keep the extension only when at least one byte of the stem survives.
	if dot > 0 && name.len - dot < limit {
		extension := name[dot..]
		return truncate_utf8(name[..dot], limit - extension.len) + extension
	}
	return truncate_utf8(name, limit)
}

// truncate_utf8 cuts a string to at most `n` bytes without splitting a rune.
fn truncate_utf8(s string, n int) string {
	if s.len <= n {
		return s
	}
	mut cut := n
	for cut > 0 && (s[cut] & 0xc0) == 0x80 {
		cut--
	}
	return s[..cut]
}
