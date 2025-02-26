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

struct type_list type_list_init(void)
{
    struct type_list list = {
        .types = NULL,
        .capacity = 0,
        .count = 0,
    };

    return list;
}

void type_list_deinit(struct type_list *list)
{
    assert(list != NULL);

    for (int i = 0; i < list->count; i++) {
        type_deinit(&list->types[i]);
    }

    if (list->types != NULL) {
        free(list->types);
    }
}

struct type *type_list_get(struct type_list *list, type_id id)
{
    if (id < 0 || id >= list->count) {
        return NULL;
    }

    return &list->types[id];
}

type_id type_list_push(struct type_list *list, struct type type)
{
    assert(list != NULL);

    if (list->types == NULL) {
        list->capacity = 8;
        list->types = malloc(sizeof(struct type) * list->capacity);
        if (list->types == NULL) {
            fprintf(stderr, "OOM\n");
            return -1;
        }
    }

    if (list->count >= list->capacity) {
        list->capacity *= 2;
        list->types = realloc(list->types, sizeof(struct type) * list->capacity);
        if (list->types == NULL) {
            fprintf(stderr, "OOM\n");
            return -1;
        }
    }

    type_id id = list->count;

    list->types[list->count++] = type;

    return id;
}
