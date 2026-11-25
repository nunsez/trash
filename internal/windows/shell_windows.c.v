module windows

// C declarations for `shell_windows.c`, which is included into the generated
// translation unit. This file is the only bridge between V and COM.

#preinclude "windows_preinclude.h"

#include "shell_windows.c"

#flag windows -lole32
#flag windows -luuid
#flag windows -lshell32
#flag windows -ladvapi32

fn C.trash_error_text(code int, buf &u8, len int)
fn C.trash_attributes(path &u16, error &int) u32
fn C.trash_is_volume_root_junction(path &u16, error &int) int
fn C.trash_path_size(path &u16, error &int) u64
fn C.trash_volume_root(path &u16, buf &u8, len int) int
fn C.trash_quota_allows(path &u16, size u64, err &u8, errlen int) int
fn C.trash_place_many(paths voidptr, count int, item_hr &int, aborted &int, err &u8, errlen int) int
