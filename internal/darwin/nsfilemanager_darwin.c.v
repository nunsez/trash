module darwin

// Objective-C runtime interop for `NSFileManager trashItemAtURL:`. Every
// message send is declared with its exact signature in this one file, because
// `objc_msgSend` has to be called through a matching function type.

#include "nsfilemanager_darwin.h"
#include <objc/runtime.h>
#include <objc/message.h>

#flag darwin -framework Foundation

fn C.objc_getClass(name &char) voidptr
fn C.sel_registerName(name &char) voidptr
fn C.objc_msgSend(self voidptr, op voidptr, ...) voidptr
fn C.objc_autoreleasePoolPush() voidptr
fn C.objc_autoreleasePoolPop(pool voidptr)

// MsgSendNoArg is `id (*)(id, SEL)`.
type MsgSendNoArg = fn (obj voidptr, sel voidptr) voidptr

// MsgSendArg is `id (*)(id, SEL, id)`.
type MsgSendArg = fn (obj voidptr, sel voidptr, arg voidptr) voidptr

// MsgSendTrash is
// `BOOL (*)(id, SEL, NSURL *, NSURL **, NSError **)`.
type MsgSendTrash = fn (obj voidptr, sel voidptr, url voidptr, out &voidptr, err &voidptr) i8

// trash_item moves `path` into the system trash and returns the absolute path
// the system chose inside the trash.
fn trash_item(path string) !string {
	pool := C.objc_autoreleasePoolPush()
	defer {
		C.objc_autoreleasePoolPop(pool)
	}
	no_arg := unsafe { MsgSendNoArg(C.objc_msgSend) }
	with_arg := unsafe { MsgSendArg(C.objc_msgSend) }

	nsstring := C.objc_getClass(c'NSString')
	with_utf8 := C.sel_registerName(c'stringWithUTF8String:')
	path_string := with_arg(nsstring, with_utf8, path.str)
	if isnil(path_string) {
		return error('cannot represent the path as an NSString')
	}
	nsurl := C.objc_getClass(c'NSURL')
	from_path := C.sel_registerName(c'fileURLWithPath:')
	url := with_arg(nsurl, from_path, path_string)
	if isnil(url) {
		return error('cannot represent the path as an NSURL')
	}

	nsfilemanager := C.objc_getClass(c'NSFileManager')
	default_manager := C.sel_registerName(c'defaultManager')
	manager := no_arg(nsfilemanager, default_manager)
	if isnil(manager) {
		return error('cannot reach NSFileManager')
	}

	trash_sel := C.sel_registerName(c'trashItemAtURL:resultingItemURL:error:')
	trash := unsafe { MsgSendTrash(C.objc_msgSend) }
	mut result_url := voidptr(0)
	mut error_obj := voidptr(0)
	ok := trash(manager, trash_sel, url, &result_url, &error_obj)
	if ok == 0 {
		return error(error_text(error_obj))
	}
	if isnil(result_url) {
		return error('the system reported no trash path')
	}
	path_sel := C.sel_registerName(c'path')
	result := no_arg(result_url, path_sel)
	utf8_sel := C.sel_registerName(c'UTF8String')
	utf8 := no_arg(result, utf8_sel)
	if isnil(utf8) {
		return error('the system reported no trash path')
	}
	return unsafe { cstring_to_vstring(&char(utf8)) }
}

// error_text renders an `NSError` with its localized description.
fn error_text(error_obj voidptr) string {
	if isnil(error_obj) {
		return 'the system refused to trash the item'
	}
	no_arg := unsafe { MsgSendNoArg(C.objc_msgSend) }
	description_sel := C.sel_registerName(c'localizedDescription')
	description := no_arg(error_obj, description_sel)
	if isnil(description) {
		return 'the system refused to trash the item'
	}
	utf8_sel := C.sel_registerName(c'UTF8String')
	utf8 := no_arg(description, utf8_sel)
	if isnil(utf8) {
		return 'the system refused to trash the item'
	}
	return unsafe { cstring_to_vstring(&char(utf8)) }
}
