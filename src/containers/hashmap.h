#ifndef LANG_CONTAINERS_HASHMAP_H
#define LANG_CONTAINERS_HASHMAP_H

typedef void (*pfn_hashmap_destructor)(void *ptr);

struct hashmap {
    pfn_hashmap_destructor destructor;
    void **bytes;
    int size;
    int capacity;
    int type_size;
};

struct hashmap hashmap_init(int type_size, pfn_hashmap_destructor destructor);
void hashmap_deinit(struct hashmap *map);
void hashmap_insert(struct hashmap *map, const char *key, int key_len, const void *data);
void hashmap_delete(struct hashmap *map, const char *key, int key_len);
void *hashmap_get(struct hashmap *map, const char *key, int key_len);

#endif
