module trashcli

// This file is the single source of truth for the CLI surface: the
// parser, the help text and the validation all read `flags` and nothing else.

// version is printed by `--version`. It must stay equal to the `version:` field
// of `v.mod`, which `version_test.v` checks.
pub const version = '0.1.0'

// FlagKind is what a flag does, independent of its spelling.
pub enum FlagKind {
	force
	recursive
	dir
	verbose
	help
	version
}

// Flag is one accepted flag with all of its spellings.
pub struct Flag {
pub:
	shorts string   // e.g. 'rR'
	longs  []string // e.g. ['recursive']
	kind   FlagKind
	help   string // the line printed by --help; '' for an alias row
}

// flags returns the whole supported surface.
pub fn flags() []Flag {
	return [
		Flag{
			shorts: 'f'
			longs:  ['force']
			kind:   .force
			help:   'ignore missing targets; never changes the exit status'
		},
		Flag{
			shorts: 'rR'
			longs:  []
			kind:   .recursive
			help:   'trash a directory and its contents'
		},
		Flag{
			shorts: 'd'
			longs:  ['dir']
			kind:   .dir
			help:   'trash an empty directory without -r'
		},
		Flag{
			shorts: 'v'
			longs:  ['verbose']
			kind:   .verbose
			help:   'print "trashed \'FILE\'" for every target that was moved'
		},
		Flag{
			shorts: ''
			longs:  ['help']
			kind:   .help
			help:   'print this help and exit'
		},
		Flag{
			shorts: ''
			longs:  ['version']
			kind:   .version
			help:   'print the version and exit'
		},
	]
}

// find_short returns the flag bound to a short option letter.
fn find_short(letter u8) ?Flag {
	for flag in flags() {
		if flag.shorts.contains_u8(letter) {
			return flag
		}
	}
	return none
}

// find_long returns the flag bound to a long option name.
fn find_long(name string) ?Flag {
	for flag in flags() {
		if name in flag.longs {
			return flag
		}
	}
	return none
}
