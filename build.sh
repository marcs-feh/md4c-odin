cc=clang 
cflags='-Os -Wall -Wextra -std=c11 -fno-strict-aliasing -fwrapv -fPIC -Wno-macro-redefined'

set -xeu

$cc $cflags -o md4c.o -c \
	-DMD_VERSION_MAJOR=0 \
	-DMD_VERSION_MINOR=5 \
	-DMD_VERSION_RELEASE=2 \
	src/lib.c

