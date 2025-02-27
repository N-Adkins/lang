#include "hashmap.h"

#include <stdlib.h>

const int DEFAULT_CAPACITY = 16;

#define BUCKET_SIZE(type_size) (((sizeof(int) + sizeof(char *) + type_size) + 7) & ~7);
#define BUCKET_KEY_LEN(ptr) ((int *)(char *)ptr)
#define BUCKET_KEY(ptr) ((char **)((char *)ptr + sizeof(int)))
#define BUCKET_VALUE(ptr) ((void *)((char *)ptr + sizeof(int) + sizeof(char *)))

static unsigned int fnv1a_hash(const char *str, int len) 
{
    static const unsigned int FNV1A_PRIME = 0x811C9DC5;

    unsigned int hash = 0;
    for (int i = 0; i < len; i++) {
        hash *= FNV1A_PRIME; 
        hash ^= str[i];
    }

    return hash;
}

struct hashmap hashmap_init(int type_size, pfn_hashmap_destructor destructor)
{
    struct hashmap map = {
        .bytes = NULL,
        .size = 0,
        .capacity = DEFAULT_CAPACITY,
        .type_size = type_size,
        .destructor = destructor,
    };

    return map;
}

void hashmap_deinit(struct hashmap *map)
{
    const int bucket_size = BUCKET_SIZE(map->size);
    for (void **bucket = map->bytes; bucket < map->bytes + map->capacity * bucket_size; bucket += bucket_size) {
        map->destructor(BUCKET_VALUE(*bucket));
        free(bucket);
    }
    free(map->bytes);
}

void hashmap_insert(struct hashmap *map, const char *key, int key_len, const void *data)
{
    
}

void hashmap_delete(struct hashmap *map, const char *key, int key_len)
{

}

void *hashmap_get(struct hashmap *map, const char *key, int key_len)
{

}
