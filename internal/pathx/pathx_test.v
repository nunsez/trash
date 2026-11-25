module pathx

fn test_parse_splits_components() {
	assert parse('/').is_root()
	assert parse('//').is_root()
	assert parse('///').is_root()
	assert !parse('').is_root()
	assert !parse('.').is_root()

	p := parse('/a/b/c')
	assert p.absolute
	assert !p.trailing_sep
	assert p.components == ['a', 'b', 'c']
	assert p.name() == 'c'
	assert p.dirs() == ['a', 'b']

	q := parse('a//b/')
	assert !q.absolute
	assert q.trailing_sep
	assert q.components == ['a', 'b']

	r := parse('./a')
	assert r.components == ['.', 'a']
	assert r.dirs() == ['.']

	assert parse('a/.').name() == '.'
	assert parse('..').name() == '..'
	assert parse('').name() == ''
}

fn test_parent_arg() {
	// The parent is what `realpath` is applied to.
	assert parse('/a/b/c').parent_arg() == '/a/b'
	assert parse('/a').parent_arg() == '/'
	assert parse('a/b').parent_arg() == 'a'
	assert parse('a').parent_arg() == '.'
	assert parse('a/').parent_arg() == '.'
	assert parse('../a').parent_arg() == '..'
	assert parse('/a/b/').parent_arg() == '/a'
}

fn test_join_handles_root() {
	assert join('/', 'x') == '/x'
	assert join('/a', 'x') == '/a/x'
}

fn test_normalize_strips_trailing_separators() {
	assert normalize('/a/b/') == '/a/b'
	assert normalize('/a/b///') == '/a/b'
	assert normalize('/') == '/'
	assert normalize('//') == '/'
}

fn test_covers() {
	assert covers('/', '/a')
	assert covers('/a', '/a')
	assert covers('/a', '/a/b')
	assert !covers('/a', '/ab')
	assert !covers('/a/b', '/a')
}

fn test_decode_escapes() {
	assert decode_escapes('/mnt/a\\040b') == '/mnt/a b'
	assert decode_escapes('\\011tab') == '\ttab'
	assert decode_escapes('back\\134slash') == 'back\\slash'
	assert decode_escapes('plain') == 'plain'
	assert decode_escapes('\\40') == '\\40' // too short, kept as it is
	assert decode_escapes('\\999') == '\\999' // not octal
}

fn test_parse_mountinfo() {
	text := '36 35 98:0 /mnt1 /mnt1 rw,noatime master:1 - ext3 /dev/root rw
22 1 8:1 / / rw,relatime - ext4 /dev/sda1 rw
30 22 0:24 / /mnt/with\\040space rw - tmpfs tmpfs rw
'
	assert parse_mountinfo(text) == ['/mnt1', '/', '/mnt/with space']
}

fn test_mount_queries() {
	mounts := ['/', '/proc', '/mnt/disk']
	assert is_mount_point('/', mounts)
	assert is_mount_point('/proc', mounts)
	assert is_mount_point('/proc/', mounts)
	assert !is_mount_point('/proc/self', mounts)
	assert contains_mount_point('/', mounts)
	assert contains_mount_point('/mnt', mounts)
	assert !contains_mount_point('/proc', mounts)
	assert !contains_mount_point('/mnt/disk', mounts)
}

fn test_topdir() {
	mounts := ['/', '/mnt/disk', '/home']
	assert topdir('/mnt/disk/a/b', mounts) == '/mnt/disk'
	assert topdir('/mnt/other', mounts) == '/'
	assert topdir('/home/u/x', mounts) == '/home'
	assert topdir('/', mounts) == '/'
	assert topdir('/a/b', []) == '/'
}
