#include "list.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

const int DEFAULT_CAPACITY = 8;

struct dynarray dynarray_init(int type_size, pfn_list_destructor destructor)
{
    struct dynarray array = {
        .bytes = NULL,
        .size = 0,
        .capacity = DEFAULT_CAPACITY,
        .type_size = type_size,
        .destructor = destructor,
    };

    return array;
}

void dynarray_deinit(struct dynarray *array)
{
    for (int i = 0; i < array->size; i++) {
        array->destructor(dynarray_get(array, i));
    }

    if (array->bytes != NULL) {
        free(array->bytes);
    }
}

void dynarray_push(struct dynarray *array, const void *data)
{
    assert(array != NULL);
    assert(data != NULL);

    if (array->bytes == NULL) {
        array->bytes = malloc(array->type_size * array->capacity);
        if (array->bytes == NULL) {
            fprintf(stderr, "OOM\n");
            return;
        }
    }

    if (array->size >= array->capacity) {
        array->capacity *= 2;
        array->bytes = realloc(array->bytes, array->type_size * array->capacity);
        if (array->bytes == NULL) {
            fprintf(stderr, "OOM\n");
            return;
        }
    }

    memcpy(&array->bytes[array->type_size * array->size++], data, array->type_size);
}

void *dynarray_get(struct dynarray *array, int index)
{
    assert(array != NULL);
    
    if (array->size <= index) {
        return NULL;
    }

    return &array->bytes[array->type_size * index];
}
