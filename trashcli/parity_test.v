module trashcli

import os
import trashcli.testutil

// The CLI contract is tested as a table of arguments -> exit status, output and
// effect. The sandbox helper lives in the `trashcli.testutil` subpackage, so
// every `_test.v` file in this package can use it.
fn test_usage_errors() {
	s := testutil.new_sandbox()!
	defer {
		s.done()
	}
	cases := [
		Case{
			args:   []
			code:   1
			output: 'trash: missing operand'
		},
		Case{
			args:   ['--bogus']
			code:   1
			output: "trash: unrecognized option '--bogus'"
		},
		Case{
			args:   ['-z']
			code:   1
			output: "trash: invalid option -- 'z'"
		},
		Case{
			args:   ['-fz']
			code:   1
			output: "trash: invalid option -- 'z'"
		},
		Case{
			args:   ['-i']
			code:   1
			output: "trash: invalid option -- 'i'"
		},
		Case{
			args:   ['-I']
			code:   1
			output: "trash: invalid option -- 'I'"
		},
		Case{
			args:   ['--interactive']
			code:   1
			output: "trash: unrecognized option '--interactive'"
		},
		Case{
			args:   ['--recursive']
			code:   1
			output: "trash: unrecognized option '--recursive'"
		},
		Case{
			args:   ['--force=1']
			code:   1
			output: "trash: unrecognized option '--force=1'"
		},
		Case{
			args:   ['-x']
			code:   1
			output: "trash: invalid option -- 'x'"
		},
	]
	for c in cases {
		res := s.exec(c.args)
		assert res.exit_code == c.code, '${c.args}: expected ${c.code}, got ${res.exit_code} (${res.output})'
		assert res.output.contains(c.output), '${c.args}: expected "${c.output}" in "${res.output}"'
	}
}

fn test_help_and_version_win() {
	s := testutil.new_sandbox()!
	defer {
		s.done()
	}
	help := s.exec(['--help'])
	assert help.exit_code == 0
	assert help.output.contains('Usage: trash [OPTION]... FILE...')
	assert help.output.contains('Exit status: 0 when every target was trashed')
	assert help.output.contains('are rejected, not ignored')

	// `--help` wins over a bad flag and over `--version`.
	both := s.exec(['--bogus', '--help', '--version'])
	assert both.exit_code == 0
	assert both.output.contains('Usage: trash')

	printed := s.exec(['--version'])
	assert printed.exit_code == 0
	assert printed.output.trim_space() == 'trash ${trashcli.version}'
}

fn test_refusals_never_touch_the_target() {
	s := testutil.new_sandbox()!
	defer {
		s.done()
	}
	cases := [
		Case{
			args:   ['/']
			code:   1
			output: "trash: cannot trash '/': refusing to trash a filesystem root"
		},
		Case{
			args:   ['.']
			code:   1
			output: "refusing to trash '.' or '..'"
		},
		Case{
			args:   ['-r', '..']
			code:   1
			output: "refusing to trash '.' or '..'"
		},
		Case{
			args:   ['-']
			code:   1
			output: "trash: cannot trash '-': "
		},
		Case{
			args:   ['--', '--help']
			code:   1
			output: "trash: cannot trash '--help': "
		},
		Case{
			args:   ['missing']
			code:   1
			output: "trash: cannot trash 'missing': "
		},
		Case{
			args:   ['-f', 'missing']
			code:   0
			output: ''
		},
	]
	for c in cases {
		res := s.exec(c.args)
		assert res.exit_code == c.code, '${c.args}: expected ${c.code}, got ${res.exit_code} (${res.output})'
		if c.output == '' {
			assert res.output == '', '${c.args}: expected silence, got "${res.output}"'
		} else {
			assert res.output.contains(c.output), '${c.args}: expected "${c.output}" in "${res.output}"'
		}
	}
}

// Case is one row of the parity table.
struct Case {
	args   []string
	code   int
	output string
}

fn test_force_only_ignores_missing_targets() {
	s := testutil.new_sandbox()!
	defer {
		s.done()
	}
	// `/` exists, so `-f` must not turn its refusal into success.
	mut res := s.exec(['-f', '/'])
	assert res.exit_code == 1
	assert res.output.contains('refusing to trash a filesystem root')

	// A missing target is silent and does not change the exit status.
	res = s.exec(['-fv', os.join_path(s.work, 'missing')])
	assert res.exit_code == 0
	assert res.output == ''
}
