#include "symbol.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

#define GEN_TYPE_STRING(type) \
    #type,

const char *type_tag_tostring[] = {
    FOREACH_TYPE(GEN_TYPE_STRING)
};

static unsigned int fnv1a_hash(const char *str, int len) 
{
    static const unsigned int FNV1A_PRIME = 0x811c9dc5 ;

    unsigned int hash = 0;
    for (int i = 0; i < len; i++) {
        hash *= FNV1A_PRIME; 
        hash ^= str[i];
    }

    return hash;
}

struct type type_init(enum type_tag tag)
{
    struct type type = {
        .child = NULL,
        .child_capacity = 0,
        .child_count = 0,
        .tag = tag,
    };

    return type;
}

void type_deinit(struct type* type)
{
    assert(type != NULL);

    if (type->child != NULL) {
        free(type->child);
    }
}

void type_push_child(struct type *parent, type_id child)
{
    assert(parent != NULL);

    if (parent->child == NULL) {
        parent->child_capacity = 8;
        parent->child = malloc(sizeof(type_id) * parent->child_capacity);
        if (parent->child == NULL) {
            fprintf(stderr, "OOM\n");
            return;
        }
    }

    if (parent->child_count >= parent->child_capacity) {
        parent->child_capacity *= 2;
        parent->child = realloc(parent->child, sizeof(type_id) * parent->child_capacity);
        if (parent->child == NULL) {
            fprintf(stderr, "OOM\n");
            return;
        }
    }

    parent->child[parent->child_count++] = child;
}
