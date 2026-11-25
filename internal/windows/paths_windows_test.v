module windows

fn test_parse_drive_path() {
	p := parse('C:\\a\\b')
	assert p.absolute
	assert !p.unc
	assert p.root == 'C:\\'
	assert p.components == ['a', 'b']
	assert p.name() == 'b'
	assert !p.trailing_sep
}

fn test_parse_accepts_forward_slashes_and_trailing_separator() {
	p := parse('C:/a/b/')
	assert p.root == 'C:\\'
	assert p.components == ['a', 'b']
	assert p.name() == 'b'
	assert p.trailing_sep
}

fn test_parse_volume_root() {
	p := parse('C:\\')
	assert p.is_root()
	assert p.name() == ''
	assert !p.trailing_sep
}

fn test_parse_unc_path() {
	p := parse('\\\\server\\share\\dir\\x')
	assert p.unc
	assert p.absolute
	assert p.root == '\\\\server\\share'
	assert p.components == ['dir', 'x']
	assert p.name() == 'x'

	root := parse('\\\\server\\share')
	assert root.unc
	assert root.is_root()
}

fn test_parse_relative_path() {
	p := parse('a\\b')
	assert !p.absolute
	assert p.root == ''
	assert p.components == ['a', 'b']
}

fn test_validate_path_accepts_an_ordinary_file() {
	validate_path('C:\\Users\\me\\notes.txt', 'C:\\cwd')!
	validate_path('notes.txt', 'C:\\cwd')!
}

fn test_validate_path_refuses_a_volume_root() {
	if err := catch_validate('C:\\') {
		assert err == 'refusing to trash a filesystem root'
	} else {
		assert false, 'a volume root must be refused'
	}
}

fn test_validate_path_refuses_a_unc_path() {
	if err := catch_validate('\\\\server\\share\\x') {
		assert err == 'no usable trash directory on this volume'
	} else {
		assert false, 'a UNC path must be refused'
	}
}

fn test_validate_path_refuses_a_long_path() {
	long := 'C:\\' + 'a'.repeat(max_shell_path)
	if err := catch_validate(long) {
		assert err == 'path too long for the Recycle Bin'
	} else {
		assert false, 'a path over the shell limit must be refused'
	}
}

fn test_validate_path_counts_the_absolute_path() {
	cwd := 'C:\\' + 'a'.repeat(max_shell_path - 2)
	if err := catch_validate_in('b', cwd) {
		assert err == 'path too long for the Recycle Bin'
	} else {
		assert false, 'the resolved path must be checked, not the argument'
	}
}

fn test_validate_path_refuses_the_recycle_bin() {
	for path in ['C:\\$Recycle.Bin', 'C:\\$Recycle.Bin\\x', 'C:\\a\\$recycle.bin\\b'] {
		if err := catch_validate(path) {
			assert err == 'refusing to trash the trash directory or one of its ancestors', '${path}: ${err}'
		} else {
			assert false, '${path} must be refused'
		}
	}
}

fn test_validate_path_refuses_bare_roots() {
	for path in ['/', '\\', '//', '\\\\'] {
		if err := catch_validate(path) {
			assert err == 'refusing to trash a filesystem root', '${path}: ${err}'
		} else {
			assert false, '${path} must be refused'
		}
	}
}

fn test_validate_path_refuses_reserved_and_malformed_components() {
	for path in ['C:\\a\\CON', 'C:\\a\\con.txt', 'C:\\a\\COM1', 'C:\\a\\LPT9.log'] {
		if err := catch_validate(path) {
			assert err == 'invalid path for the Recycle Bin', '${path}: ${err}'
		} else {
			assert false, '${path} must be refused'
		}
	}
	for path in ['C:\\a\\b.', 'C:\\a\\b ', 'C:\\a\\b:c'] {
		if err := catch_validate(path) {
			assert err == 'invalid path for the Recycle Bin', '${path}: ${err}'
		} else {
			assert false, '${path} must be refused'
		}
	}
}

fn test_is_reserved_name() {
	assert is_reserved_name('CON')
	assert is_reserved_name('con')
	assert is_reserved_name('Con.txt')
	assert is_reserved_name('NUL')
	assert is_reserved_name('com9')
	assert !is_reserved_name('console')
	assert !is_reserved_name('COM0')
	assert !is_reserved_name('notes.txt')
}

fn test_same_path() {
	assert same_path('C:\\Users\\me', 'c:/users/ME/')
	assert same_path('C:\\Users\\me\\..\\me', 'C:\\Users\\me')
	assert !same_path('C:\\Users\\me', 'C:\\Users\\other')
	assert !same_path('C:\\a', 'D:\\a')
}

fn test_absolute_path() {
	assert absolute_path('C:\\a', 'D:\\cwd') == 'C:\\a'
	assert absolute_path('C:\\a\\..\\b', 'D:\\cwd') == 'C:\\b'
	assert absolute_path('b', 'C:\\a') == 'C:\\a\\b'
	assert absolute_path('.\\b', 'C:\\a') == 'C:\\a\\b'
	assert absolute_path('..\\b', 'C:\\a') == 'C:\\b'
}

// catch_validate returns the error text of `validate_path`, or '' on success.
fn catch_validate(path string) ?string {
	return catch_validate_in(path, 'C:\\cwd')
}

fn catch_validate_in(path string, cwd string) ?string {
	validate_path(path, cwd) or { return err.msg() }
	return none
}
