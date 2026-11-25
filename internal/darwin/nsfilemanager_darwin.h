// `objc_autoreleasePoolPush` and `objc_autoreleasePoolPop` are exported by
// libobjc but are not declared in the macOS SDK headers, so the prototypes are
// supplied here instead of relying on an implicit declaration (which would
// truncate the returned pointer on arm64).
#include <objc/objc.h>

void* objc_autoreleasePoolPush(void);
void objc_autoreleasePoolPop(void* pool);
