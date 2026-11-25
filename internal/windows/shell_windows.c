// COM and Win32 helpers of the Windows backend. They live in C because
// `IFileOperation` and the shell interfaces are COM vtables, and the registry
// and reparse-point APIs are plain Win32.
//
// Every function here is called from `shell_windows.c.v`; the signatures there
// must stay in sync.

#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <shellapi.h>
#include <shlwapi.h>
#include <winioctl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// `REPARSE_DATA_BUFFER` is not part of every Windows SDK (it lives in the
// WDK's `ntdef.h` on some toolchains), so define the stable prefix locally.
// Only the mount-point fields are used below.
typedef struct {
	ULONG ReparseTag;
	USHORT ReparseDataLength;
	USHORT Reserved;
	union {
		struct {
			USHORT SubstituteNameOffset;
			USHORT SubstituteNameLength;
			USHORT PrintNameOffset;
			USHORT PrintNameLength;
			ULONG Flags;
			WCHAR PathBuffer[1];
		} SymbolicLinkReparseBuffer;
		struct {
			USHORT SubstituteNameOffset;
			USHORT SubstituteNameLength;
			USHORT PrintNameOffset;
			USHORT PrintNameLength;
			WCHAR PathBuffer[1];
		} MountPointReparseBuffer;
		struct {
			UCHAR DataBuffer[1];
		} GenericReparseBuffer;
	};
} TrashReparseDataBuffer;

// trash_hr_text renders an HRESULT as UTF-8. The trailing CR/LF that
// FormatMessageW adds is trimmed.
static void trash_hr_text(HRESULT hr, char *buf, int len) {
	if (buf == NULL || len <= 0) {
		return;
	}
	buf[0] = 0;
	LPWSTR wide = NULL;
	DWORD count = FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
		FORMAT_MESSAGE_IGNORE_INSERTS, NULL, (DWORD)hr, MAKELANGID(LANG_NEUTRAL,
		SUBLANG_DEFAULT), (LPWSTR)&wide, 0, NULL);
	if (count == 0 || wide == NULL) {
		snprintf(buf, (size_t)len, "the shell API failed (HRESULT 0x%08lX)", (unsigned long)hr);
		return;
	}
	while (count > 0) {
		wchar_t last = wide[count - 1];
		if (last != L'\r' && last != L'\n' && last != L' ') {
			break;
		}
		wide[--count] = 0;
	}
	if (WideCharToMultiByte(CP_UTF8, 0, wide, -1, buf, len, NULL, NULL) == 0) {
		snprintf(buf, (size_t)len, "the shell API failed (HRESULT 0x%08lX)", (unsigned long)hr);
	}
	LocalFree(wide);
}

// trash_error_text renders a Win32 error code as UTF-8.
void trash_error_text(int code, char *buf, int len) {
	trash_hr_text(HRESULT_FROM_WIN32((DWORD)code), buf, len);
}

// trash_attributes returns the attributes of `path` and sets `error` on
// failure. The return value is 0 when `error` is set.
uint32_t trash_attributes(const uint16_t *path, int *error) {
	*error = 0;
	DWORD attributes = GetFileAttributesW((LPCWSTR)path);
	if (attributes == INVALID_FILE_ATTRIBUTES) {
		*error = (int)GetLastError();
		return 0;
	}
	return (uint32_t)attributes;
}

// trash_is_volume_root_junction reports whether `path` is a reparse point whose
// substitute name is a volume root. It returns 0 for an
// ordinary file, directory or link and -1 on failure.
int trash_is_volume_root_junction(const uint16_t *path, int *error) {
	*error = 0;
	DWORD attributes = GetFileAttributesW((LPCWSTR)path);
	if (attributes == INVALID_FILE_ATTRIBUTES) {
		*error = (int)GetLastError();
		return -1;
	}
	if ((attributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0) {
		return 0;
	}
	HANDLE handle = CreateFileW((LPCWSTR)path, 0,
		FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING,
		FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
	if (handle == INVALID_HANDLE_VALUE) {
		*error = (int)GetLastError();
		return -1;
	}
	char buffer[16 * 1024];
	DWORD returned = 0;
	BOOL ok = DeviceIoControl(handle, FSCTL_GET_REPARSE_POINT, NULL, 0, buffer, sizeof(buffer),
		&returned, NULL);
	CloseHandle(handle);
	if (!ok) {
		*error = (int)GetLastError();
		return -1;
	}
	TrashReparseDataBuffer *reparse = (TrashReparseDataBuffer *)buffer;
	if (reparse->ReparseTag != IO_REPARSE_TAG_MOUNT_POINT) {
		return 0;
	}
	WCHAR substitute[1024];
	int offset = (int)(reparse->MountPointReparseBuffer.SubstituteNameOffset / sizeof(WCHAR));
	int length = (int)(reparse->MountPointReparseBuffer.SubstituteNameLength / sizeof(WCHAR));
	if (length <= 0 || length >= (int)(sizeof(substitute) / sizeof(WCHAR))) {
		return 0;
	}
	wmemcpy(substitute, reparse->MountPointReparseBuffer.PathBuffer + offset, (size_t)length);
	substitute[length] = 0;
	const WCHAR *name = substitute;
	if (wcsncmp(name, L"\\??\\", 4) == 0) {
		name += 4;
	}
	size_t name_length = wcslen(name);
	if (name_length == 3 && name[1] == L':' && name[2] == L'\\') {
		return 1;
	}
	// `Volume{GUID}\` with no directory after it is a volume root as well.
	if (wcsncmp(name, L"Volume{", 7) == 0 && name_length > 8 && name[name_length - 1] == L'\\' &&
		wcschr(name, L'\\') == name + name_length - 1) {
		return 1;
	}
	return 0;
}

// trash_path_size sums the logical sizes below `path`. Reparse points
// are not descended into and count as zero. Returns 0 or a Win32 error code.
static int trash_size_w(const WCHAR *path, uint64_t *total) {
	WIN32_FIND_DATAW data;
	HANDLE handle = FindFirstFileW(path, &data);
	if (handle == INVALID_HANDLE_VALUE) {
		return (int)GetLastError();
	}
	FindClose(handle);
	if ((data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
		*total = 0;
		return 0;
	}
	if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
		*total = ((uint64_t)data.nFileSizeHigh << 32) | (uint64_t)data.nFileSizeLow;
		return 0;
	}
	WCHAR pattern[4096];
	if (swprintf(pattern, 4096, L"%ls\\*", path) < 0) {
		return ERROR_BUFFER_OVERFLOW;
	}
	handle = FindFirstFileW(pattern, &data);
	if (handle == INVALID_HANDLE_VALUE) {
		int code = (int)GetLastError();
		if (code == ERROR_FILE_NOT_FOUND) {
			*total = 0;
			return 0;
		}
		return code;
	}
	int result = 0;
	do {
		if (wcscmp(data.cFileName, L".") == 0 || wcscmp(data.cFileName, L"..") == 0) {
			continue;
		}
		WCHAR child[4096];
		if (swprintf(child, 4096, L"%ls\\%ls", path, data.cFileName) < 0) {
			result = ERROR_BUFFER_OVERFLOW;
			break;
		}
		uint64_t size = 0;
		result = trash_size_w(child, &size);
		if (result != 0) {
			break;
		}
		*total += size;
	} while (FindNextFileW(handle, &data));
	FindClose(handle);
	return result;
}

// trash_path_size is `trash_size_w` with an error code out-parameter.
uint64_t trash_path_size(const uint16_t *path, int *error) {
	uint64_t total = 0;
	*error = trash_size_w((const WCHAR *)path, &total);
	return *error == 0 ? total : 0;
}

// trash_recycle_capacity returns the capacity of the Recycle Bin of the volume
// that holds `path`, in bytes.
static uint64_t trash_recycle_capacity(const WCHAR *root) {
	WCHAR volume[512];
	if (GetVolumeNameForVolumeMountPointW(root, volume, 512)) {
		WCHAR *open = wcsrchr(volume, L'{');
		if (open != NULL) {
			WCHAR *close = wcschr(open, L'}');
			if (close != NULL) {
				*close = 0;
				WCHAR key[512];
				if (swprintf(key, 512,
					L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\BitBucket\\Volume\\%ls",
					open) > 0) {
					DWORD megabytes = 0;
					DWORD size = sizeof(megabytes);
					DWORD type = 0;
					if (RegGetValueW(HKEY_CURRENT_USER, key, L"MaxCapacity",
						RRF_RT_REG_DWORD, &type, &megabytes, &size) == ERROR_SUCCESS) {
						return (uint64_t)megabytes * 1024ULL * 1024ULL;
					}
				}
			}
		}
	}
	ULARGE_INTEGER total;
	if (!GetDiskFreeSpaceExW(root, NULL, &total, NULL)) {
		return 0;
	}
	// The Windows default: 10% below 40 GB, 5% otherwise.
	if (total.QuadPart < 40ULL * 1024ULL * 1024ULL * 1024ULL) {
		return total.QuadPart / 10;
	}
	return total.QuadPart / 20;
}

// trash_volume_root writes the volume root of `path` (for example `C:\`) as
// UTF-8. It returns 0 on success and a negated Win32 error code on failure.
int trash_volume_root(const uint16_t *path, char *buf, int len) {
	if (buf == NULL || len <= 0) {
		return -(int)ERROR_INVALID_PARAMETER;
	}
	buf[0] = 0;
	WCHAR root[MAX_PATH];
	if (!GetVolumePathNameW((LPCWSTR)path, root, MAX_PATH)) {
		return -(int)GetLastError();
	}
	if (WideCharToMultiByte(CP_UTF8, 0, root, -1, buf, len, NULL, NULL) == 0) {
		return -(int)GetLastError();
	}
	return 0;
}

// trash_quota_allows reports whether `size` more bytes fit into the Recycle Bin
// of the volume that holds `path`. It returns 1 when they fit, 0 when they do
// not (with the reason in `err`) and -1 when the volume cannot be inspected.
int trash_quota_allows(const uint16_t *path, uint64_t size, char *err, int errlen) {
	err[0] = 0;
	WCHAR root[MAX_PATH];
	if (!GetVolumePathNameW((LPCWSTR)path, root, MAX_PATH)) {
		trash_hr_text(HRESULT_FROM_WIN32(GetLastError()), err, errlen);
		return -1;
	}
	SHQUERYRBINFO info;
	memset(&info, 0, sizeof(info));
	info.cbSize = sizeof(info);
	if (FAILED(SHQueryRecycleBinW(root, &info))) {
		snprintf(err, (size_t)errlen, "no usable trash directory on this volume");
		return 0;
	}
	uint64_t used = (uint64_t)info.i64Size;
	uint64_t capacity = trash_recycle_capacity(root);
	if (capacity == 0) {
		snprintf(err, (size_t)errlen, "no usable trash directory on this volume");
		return 0;
	}
	if (used + size > capacity) {
		snprintf(err, (size_t)errlen, "the object does not fit in the Recycle Bin");
		return 0;
	}
	return 1;
}

// trash_place_many sends every path to the Recycle Bin in one IFileOperation.
//
// Returns 0 on success, the failing HRESULT when `PerformOperations` failed, and
// -1 when the operation itself could not be created (the message is in `err`).
// `item_hr[i]` receives the HRESULT of a path that could not even be added to
// the operation, `aborted` is set when the shell reported an aborted operation.
int trash_place_many(void **paths, int count, int *item_hr, int *aborted, char *err, int errlen) {
	err[0] = 0;
	*aborted = 0;
	for (int i = 0; i < count; i++) {
		item_hr[i] = 0;
	}
	HRESULT initialized = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
	BOOL owns_com = SUCCEEDED(initialized);
	if (FAILED(initialized) && initialized != RPC_E_CHANGED_MODE) {
		trash_hr_text(initialized, err, errlen);
		return -1;
	}
	IFileOperation *operation = NULL;
	HRESULT result = CoCreateInstance(&CLSID_FileOperation, NULL, CLSCTX_ALL,
		&IID_IFileOperation, (void **)&operation);
	if (FAILED(result) || operation == NULL) {
		trash_hr_text(result, err, errlen);
		if (owns_com) {
			CoUninitialize();
		}
		return -1;
	}
	result = operation->lpVtbl->SetOperationFlags(operation, FOF_ALLOWUNDO | FOF_NO_UI);
	if (FAILED(result)) {
		// Without FOF_ALLOWUNDO the shell may delete permanently, which this tool
		// must never do, so the whole operation is abandoned.
		trash_hr_text(result, err, errlen);
		operation->lpVtbl->Release(operation);
		if (owns_com) {
			CoUninitialize();
		}
		return -1;
	}
	int added = 0;
	for (int i = 0; i < count; i++) {
		IShellItem *item = NULL;
		HRESULT item_result = SHCreateItemFromParsingName((PCWSTR)paths[i], NULL, &IID_IShellItem,
			(void **)&item);
		if (FAILED(item_result) || item == NULL) {
			item_hr[i] = (int)item_result;
			continue;
		}
		item_result = operation->lpVtbl->DeleteItem(operation, item, NULL);
		item->lpVtbl->Release(item);
		if (FAILED(item_result)) {
			item_hr[i] = (int)item_result;
			continue;
		}
		added++;
	}
	result = S_OK;
	if (added > 0) {
		result = operation->lpVtbl->PerformOperations(operation);
		if (SUCCEEDED(result)) {
			BOOL was_aborted = FALSE;
			if (SUCCEEDED(operation->lpVtbl->GetAnyOperationsAborted(operation, &was_aborted))) {
				*aborted = was_aborted ? 1 : 0;
			}
		}
	}
	operation->lpVtbl->Release(operation);
	if (owns_com) {
		CoUninitialize();
	}
	if (FAILED(result)) {
		trash_hr_text(result, err, errlen);
		return (int)result;
	}
	return 0;
}
