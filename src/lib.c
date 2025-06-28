#include "md4c.c"
#include "md4c-html.c"
#include "entity.c"

_Static_assert(sizeof(MD_OFFSET) == sizeof(uint32_t), "Invalid offset type");
_Static_assert(sizeof(MD_SIZE) == sizeof(uint32_t), "Invalid size type");
_Static_assert(sizeof(MD_CHAR) == sizeof(char), "Invalid char type");

