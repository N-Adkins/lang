#include "hashmap.h"

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

const int HASHMAP_DEFAULT_CAPACITY = 16;

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

static void *bucket_init(int type_size, const char *key, int key_len, const void *value)
{
    const int bucket_size = BUCKET_SIZE(type_size);

    void *bucket = malloc(bucket_size);
    if (bucket == NULL) {
        fprintf(stderr, "OOM\n");
        return NULL;
    }

    *BUCKET_KEY_LEN(bucket) = key_len;
    *BUCKET_KEY(bucket) = malloc(key_len + 1);
    if (*BUCKET_KEY(bucket) == NULL) {
        fprintf(stderr, "OOM\n");
        return NULL;
    }
    memcpy(BUCKET_KEY(bucket), key, key_len);
    *BUCKET_KEY(bucket)[key_len] = '\0';
    memcpy(BUCKET_VALUE(bucket), value, type_size);

    return bucket;
}

void bucket_deinit(void *bucket)
{
    free(*BUCKET_KEY(bucket));
    free(bucket);
}

struct hashmap hashmap_init(int type_size, pfn_hashmap_destructor destructor)
{
    struct hashmap map = {
        .bytes = NULL,
        .size = 0,
        .capacity = HASHMAP_DEFAULT_CAPACITY,
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
        free(*bucket);
    }
    free(map->bytes);
}

void hashmap_insert(struct hashmap *map, const char *key, int key_len, const void *data)
{
    const int bucket_size = BUCKET_SIZE(map->type_size);

    if (map->bytes == NULL) {
        map->bytes = calloc(map->capacity, bucket_size);
        if (map->bytes == NULL) {
            fprintf(stderr, "OOM\n");
            return;
        }
    }
    
    const unsigned int hash = fnv1a_hash(key, key_len) % map->capacity;
    int i = 0;
    void **bucket = NULL;
    do {
        const int index = hash + i * i;
        i++;
        bucket = &map->bytes[index * bucket_size];
    } while(*bucket != NULL && strcmp(*BUCKET_KEY(*bucket), key) != 0);

    if (*bucket == NULL) {
        *bucket = bucket_init(map->type_size, key, key_len, data);
    } else { // new value
        if (map->destructor != NULL) {
            map->destructor(BUCKET_VALUE(*bucket));
        }
        memcpy(BUCKET_VALUE(*bucket), data, map->type_size);
    }
}

void hashmap_delete(struct hashmap *map, const char *key, int key_len)
{
    const int bucket_size = BUCKET_SIZE(map->type_size);

    const unsigned int hash = fnv1a_hash(key, key_len) % map->capacity;
    int i = 0;
    void **bucket = NULL;
    do {
        const int index = hash + i * i;
        i++;
        bucket = &map->bytes[index * bucket_size];
        if (strcmp(*BUCKET_KEY(*bucket), key) == 0) {
            break;
        }
    } while(*bucket != NULL);
    
    // Key exists
    if (*bucket != NULL) {
        if (map->destructor != NULL) {
            map->destructor(BUCKET_VALUE(*bucket));
        }
        bucket_deinit(*bucket);
        *bucket = NULL;
    }
}

void *hashmap_get(struct hashmap *map, const char *key, int key_len)
{
    const int bucket_size = BUCKET_SIZE(map->type_size);

    const unsigned int hash = fnv1a_hash(key, key_len) % map->capacity;
    int i = 0;
    void **bucket = NULL;
    do {
        const int index = hash + i * i;
        i++;
        bucket = &map->bytes[index * bucket_size];
        if (strcmp(*BUCKET_KEY(*bucket), key) == 0) {
            break;
        }
    } while(*bucket != NULL);
    
    // Key exists
    if (*bucket != NULL) {
        return BUCKET_VALUE(bucket);
    } else {
        return NULL;
    }
}
