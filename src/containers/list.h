#ifndef LANG_CONTAINERS_LIST_H
#define LANG_CONTAINERS_LIST_H

typedef void (*pfn_list_destructor)(void *ptr);

struct dynarray {
    pfn_list_destructor destructor;
    char *bytes;
    int capacity;
    int size;
    int type_size;
};

struct dynarray dynarray_init(int type_size, pfn_list_destructor destructor);
void dynarray_deinit(struct dynarray *array);
void dynarray_push(struct dynarray *array, const void *data);
void *dynarray_get(struct dynarray *array, int index);

#define DYNARRAY_FOREACH(array, T, var_name) \
    for (T *var_name = (T*)array->bytes[0]; var_name < (array->bytes + (array->size * array->type_size)); var_name = ((char*)var_name) + array->type_size)

#endif
