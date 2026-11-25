module trashcli

import strings

// help_text renders `--help` from the flag table, so the text cannot drift away
// from what the parser accepts.
pub fn help_text() string {
	mut out := 'Usage: trash [OPTION]... FILE...\n'
	out += 'Move each FILE into the system trash instead of deleting it.\n\n'
	for flag in flags() {
		if flag.help == '' {
			continue
		}
		out += '  ${strings.pad_right(spellings(flag), column, ' ')}${flag.help}\n'
	}
	out += '  ${strings.pad_right('--', column, ' ')}end of options\n'
	out += '\nExit status: 0 when every target was trashed, 1 when any of them failed.\n'
	out += 'Nothing is ever deleted permanently: a target that cannot be trashed is an error.\n'
	out += 'rm flags outside this list (-i, -I, --interactive, --recursive, -x, -P, -W and\n'
	out += 'the --preserve-root family) are rejected, not ignored.\n'
	return out
}

// column is the width of the spelling column of the flag list.
const column = 16

// spellings joins every spelling of a flag for the help text.
fn spellings(flag Flag) string {
	mut parts := []string{cap: flag.shorts.len + flag.longs.len}
	for short in flag.shorts {
		parts << '-${short.ascii_str()}'
	}
	for long in flag.longs {
		parts << '--${long}'
	}
	return parts.join(', ')
}
