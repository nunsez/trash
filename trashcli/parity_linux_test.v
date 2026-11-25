module trashcli

import os
import trashcli.testutil

// These tests assert the Linux trash layout, so they live in a Linux-only test
// file. The macOS backend writes to the real `~/.Trash`, and Windows uses the
// Recycle Bin, so neither can run the success paths in a sandbox.

fn test_put_end_to_end_through_the_cli() {
	s := testutil.new_sandbox()!
	defer {
		s.done()
	}
	file := os.join_path(s.work, 'a.txt')
	os.write_file(file, 'hi')!

	res := s.exec(['-v', file])
	assert res.exit_code == 0
	assert res.output.trim_space() == "trashed '${file}'"
	assert !os.exists(file)

	trash_root := os.join_path(s.data, 'Trash')
	assert os.read_file(os.join_path(trash_root, 'files', 'a.txt'))! == 'hi'
	assert os.exists(os.join_path(trash_root, 'info', 'a.txt.trashinfo'))
}

fn test_directory_rules_through_the_cli() {
	s := testutil.new_sandbox()!
	defer {
		s.done()
	}
	dir := os.join_path(s.work, 'd')
	os.mkdir_all(os.join_path(dir, 'inner'))!

	mut res := s.exec([dir])
	assert res.exit_code == 1
	assert res.output.contains('Is a directory')
	assert os.exists(dir)

	res = s.exec(['-d', dir])
	assert res.exit_code == 1
	assert res.output.contains('Directory not empty')
	assert os.exists(dir)

	res = s.exec(['-r', dir])
	assert res.exit_code == 0
	assert res.output == ''
	assert !os.exists(dir)
	assert os.exists(os.join_path(s.data, 'Trash', 'files', 'd', 'inner'))
}

fn test_empty_directory_with_dir_flag() {
	s := testutil.new_sandbox()!
	defer {
		s.done()
	}
	dir := os.join_path(s.work, 'empty')
	os.mkdir_all(dir)!
	res := s.exec(['-d', dir])
	assert res.exit_code == 0
	assert !os.exists(dir)
	assert os.is_dir(os.join_path(s.data, 'Trash', 'files', 'empty'))
}

fn test_multiple_targets_are_independent() {
	s := testutil.new_sandbox()!
	defer {
		s.done()
	}
	good := os.join_path(s.work, 'good')
	os.write_file(good, '')!
	missing := os.join_path(s.work, 'missing')

	res := s.exec([missing, good])
	assert res.exit_code == 1
	assert res.output.contains("cannot trash '${missing}'")
	assert !res.output.contains("cannot trash '${good}'")
	assert !os.exists(good)
	assert os.exists(os.join_path(s.data, 'Trash', 'files', 'good'))
}

fn test_verbose_is_silent_without_the_flag() {
	s := testutil.new_sandbox()!
	defer {
		s.done()
	}
	file := os.join_path(s.work, 'quiet')
	os.write_file(file, '')!
	res := s.exec([file])
	assert res.exit_code == 0
	assert res.output == ''
}
