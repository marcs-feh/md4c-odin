cc=clang 
cflags='-Os -Wall -Wextra -std=c11 -fno-strict-aliasing -fwrapv -fPIC -Wno-macro-redefined'

debug=0

set -xeu

if [ $debug = 1 ]; then
	$cc $cflags -O0 -g -fsanitize=address -o md4c.o -c \
		-DMD_VERSION_MAJOR=0 \
		-DMD_VERSION_MINOR=5 \
		-DMD_VERSION_RELEASE=2 \
		lib.c
else
	$cc $cflags -o md4c.o -c \
	-DMD_VERSION_MAJOR=0 \
	-DMD_VERSION_MINOR=0 \
	-DMD_VERSION_RELEASE=0 \
	lib.c
fi
