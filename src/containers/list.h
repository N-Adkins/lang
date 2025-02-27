#ifndef LANG_CONTAINERS_LIST_H
#define LANG_CONTAINERS_LIST_H

typedef void (*pfn_list_destructor)(void *ptr);

struct dynarray {
    char *bytes;
    int capacity;
    int size;
    int type_size;
    pfn_list_destructor destructor;
};

struct dynarray dynarray_init(int type_size, pfn_list_destructor destructor);
void dynarray_deinit(struct dynarray *array);
void dynarray_push(struct dynarray *array, const void *data);
void *dynarray_get(struct dynarray *array, int index);

#endif
