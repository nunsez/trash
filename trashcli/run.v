module trashcli

import trash

// run executes one command line and returns the process exit status.
pub fn run(args []string) int {
	inv := parse(args) or {
		eprintln('trash: ${err.msg()}')
		return 1
	}
	if inv.help {
		print(help_text())
		return 0
	}
	if inv.version {
		println('trash ${version}')
		return 0
	}
	if inv.targets.len == 0 {
		eprintln('trash: missing operand')
		return 1
	}
	mut failed := false
	for result in trash.put(inv.targets, inv.opts) {
		if result.reason != '' {
			eprintln("trash: cannot trash '${result.path}': ${result.reason}")
			failed = true
			continue
		}
		if inv.verbose && result.trashed {
			println("trashed '${result.path}'")
		}
	}
	return if failed { 1 } else { 0 }
}
