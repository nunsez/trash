module trashcli

import trash

// Invocation is the result of parsing `argv`.
pub struct Invocation {
pub mut:
	opts    trash.PutOptions
	verbose bool
	targets []string
	help    bool
	version bool
}

// UsageError is a rejection of the command line itself. Its text is printed as
// `trash: <text>` on stderr with exit status 1.
pub struct UsageError {
	Error
	text string
}

// msg returns the text without the `trash:` prefix.
pub fn (e UsageError) msg() string {
	return e.text
}

fn usage_error(text string) UsageError {
	return UsageError{
		text: text
	}
}

// parse turns `argv` into an Invocation. `--help` and `--version` win over
// everything else, so they are collected first.
pub fn parse(args []string) !Invocation {
	mut inv := Invocation{}
	if help_requested(args) {
		inv.help = true
		return inv
	}
	if version_requested(args) {
		inv.version = true
		return inv
	}
	mut parsing_flags := true
	for arg in args {
		if !parsing_flags {
			inv.targets << arg
			continue
		}
		if arg == '--' {
			parsing_flags = false
			continue
		}
		if arg == '-' || !arg.starts_with('-') {
			inv.targets << arg
			continue
		}
		if arg.starts_with('--') {
			flag := find_long(arg[2..]) or { return usage_error("unrecognized option '${arg}'") }
			inv.apply(flag)
			continue
		}
		for letter in arg[1..] {
			flag := find_short(letter) or {
				return usage_error("invalid option -- '${letter.ascii_str()}'")
			}
			inv.apply(flag)
		}
	}
	return inv
}

// apply records a recognised flag.
fn (mut inv Invocation) apply(flag Flag) {
	match flag.kind {
		.force {
			inv.opts.force = true
		}
		.recursive {
			inv.opts.recursive = true
		}
		.dir {
			inv.opts.dir = true
		}
		.verbose {
			inv.verbose = true
		}
		.help, .version {
			// Handled before the loop; reaching this point is impossible.
		}
	}
}

// help_requested scans for `--help` before the first `--`.
fn help_requested(args []string) bool {
	return long_option_present(args, 'help')
}

// version_requested scans for `--version` before the first `--`.
fn version_requested(args []string) bool {
	return long_option_present(args, 'version')
}

fn long_option_present(args []string, name string) bool {
	for arg in args {
		if arg == '--' {
			return false
		}
		if arg == '--${name}' {
			return true
		}
	}
	return false
}
