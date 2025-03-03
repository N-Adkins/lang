#include "symbol.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

#define GEN_TYPE_STRING(type) \
    #type,

const char *type_tag_tostring[] = {
    FOREACH_TYPE(GEN_TYPE_STRING)
};

struct type type_init(enum type_tag tag)
{
    struct type type = {
        .child = dynarray_init(sizeof(type_id), NULL),
        .tag = tag,
    };

    return type;
}

void type_deinit(struct type* type)
{
    assert(type != NULL);

    dynarray_deinit(&type->child);
}
