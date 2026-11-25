#ifndef TRASH_WINDOWS_PREINCLUDE_H
#define TRASH_WINDOWS_PREINCLUDE_H

// The shell APIs used by the backend (IFileOperation, SHQueryRecycleBinW,
// REPARSE_DATA_BUFFER) are guarded by the SDK's target-version macros. Define
// them before any Windows header is included, so an older compiler default does
// not hide the declarations.

#ifndef WINVER
#define WINVER 0x0601
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif
#ifndef NTDDI_VERSION
#define NTDDI_VERSION 0x06010000
#endif

#endif
