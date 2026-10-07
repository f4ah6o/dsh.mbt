#ifndef DSH_IOS_SYS_RANDOM_H
#define DSH_IOS_SYS_RANDOM_H

#if defined(__has_include_next) && __has_include_next(<sys/random.h>)
#include_next <sys/random.h>
#else

#include <errno.h>
#include <stddef.h>
#include <stdlib.h>

/* Apple exposes the same system CSPRNG through arc4random_buf on iOS. */
static inline int getentropy(void *buffer, size_t length) {
  if (length > 256) {
    errno = EIO;
    return -1;
  }
  arc4random_buf(buffer, length);
  return 0;
}

#endif

#endif
