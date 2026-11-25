module freedesktop

import time

fn fixed_time() time.Time {
	return time.Time{
		year:   2025
		month:  3
		day:    8
		hour:   10
		minute: 3
		second: 8
	}
}

fn test_encode_path_keeps_the_literal_set() {
	assert encode_path('home/u/a-b_c.d~e') == 'home/u/a-b_c.d~e'
	assert encode_path('a b') == 'a%20b'
	assert encode_path('100%') == '100%25'
	assert encode_path('#1') == '%231'
	assert encode_path('a\tb') == 'a%09b'
}

fn test_encode_path_is_byte_wise_for_non_ascii() {
	// `ä` is 0xC3 0xA4 in UTF-8, so it becomes two escapes.
	assert encode_path('ä') == '%C3%A4'
}

fn test_trashinfo_content() {
	content := trashinfo('home/u/a b.txt', fixed_time())
	assert content == '[Trash Info]\nPath=home/u/a%20b.txt\nDeletionDate=2025-03-08T10:03:08\n'
}

fn test_shorten_name_keeps_the_extension() {
	name := 'abcdefghij.txt'
	assert shorten_name(name, 8) == 'abcd.txt'
	assert shorten_name(name, 4) == 'abcd'
	assert shorten_name('short.txt', 9) == 'short.txt'
	assert shorten_name('no-extension', 4) == 'no-e'
}

fn test_shorten_name_does_not_split_a_rune() {
	// Four two-byte runes; cutting at 5 bytes must not leave half a rune.
	assert shorten_name('ääää', 5) == 'ää'
	assert shorten_name('.ääää', 6) == '.ää'
}
