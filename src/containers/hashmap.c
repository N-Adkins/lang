#include "hashmap.h"

#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

const int HASHMAP_DEFAULT_CAPACITY = 16;

#define BUCKET_SIZE(type_size) (((sizeof(void*)*2 + type_size) + 7) & ~7)
#define BUCKET_KEY_LEN(ptr) ((int *)(char *)ptr)
#define BUCKET_KEY(ptr) ((char **)((char *)ptr + sizeof(void*)))
#define BUCKET_VALUE(ptr) ((void *)((char *)ptr + sizeof(void*)*2))

static unsigned int fnv1a_hash(const char *str, int len) 
{
    assert(str != NULL);
    assert(len > 0);

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
    assert(key != NULL);
    assert(key_len > 0);
    assert(value != NULL);

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
    memcpy(*BUCKET_KEY(bucket), key, key_len);
    (*BUCKET_KEY(bucket))[key_len] = '\0';
    memcpy(BUCKET_VALUE(bucket), value, type_size);

    return bucket;
}

static void bucket_deinit(void *bucket)
{
    assert(bucket != NULL);

    free(*BUCKET_KEY(bucket));
    free(bucket);
}

static void hashmap_rehash(struct hashmap *map)
{
    assert(map != NULL);
    assert(map->size * 2 >= map->capacity);

    const int old_capacity = map->capacity;
    map->capacity *= 2;

    void **new_buckets = calloc(map->capacity, sizeof(void*));

    for (int i = 0; i < old_capacity; i++) {
        void *bucket = map->buckets[i];
        if (bucket == NULL) {
            continue;
        }
        
        const unsigned int hash = fnv1a_hash(*BUCKET_KEY(bucket), *BUCKET_KEY_LEN(bucket));
        int j = 0;
        void **new_bucket = NULL;
        do {
            const int index = (hash + j * j) % map->capacity;
            j++;
            new_bucket = &new_buckets[index];
        } while(*new_bucket != NULL);

        *new_bucket = bucket;
    }

    free(map->buckets);
    map->buckets = new_buckets;
}

struct hashmap hashmap_init(int type_size, pfn_hashmap_destructor destructor)
{
    struct hashmap map = {
        .buckets = NULL,
        .size = 0,
        .capacity = HASHMAP_DEFAULT_CAPACITY,
        .type_size = type_size,
        .destructor = destructor,
    };

    return map;
}

void hashmap_deinit(struct hashmap *map)
{
    assert(map != NULL);

    for (int i = 0; i < map->capacity; i++) {
        void *bucket = map->buckets[i];
        if (bucket == NULL) {
            continue;
        }

        if (map->destructor != NULL) {
            map->destructor(BUCKET_VALUE(bucket));
        }
        bucket_deinit(bucket);
    }
    free(map->buckets);
}

void hashmap_insert(struct hashmap *map, const char *key, int key_len, const void *data)
{
    assert(map != NULL);
    assert(key != NULL);
    assert(key_len > 0);
    assert(data != NULL);

    if (map->buckets == NULL) {
        map->buckets = calloc(map->capacity, sizeof(void*));
        if (map->buckets == NULL) {
            fprintf(stderr, "OOM\n");
            return;
        }
    }
    
    if (map->size * 2 >= map->capacity) {
        hashmap_rehash(map);
    }
    
    const unsigned int hash = fnv1a_hash(key, key_len);
    int i = 0;
    void **bucket = NULL;
    do {
        const int index = (hash + i * i) % map->capacity;
        i++;
        bucket = &map->buckets[index];
    } while(*bucket != NULL && strcmp(*BUCKET_KEY(*bucket), key) != 0);

    if (*bucket == NULL) {
        *bucket = bucket_init(map->type_size, key, key_len, data);
        map->size++;
    } else { // new value
        if (map->destructor != NULL) {
            map->destructor(BUCKET_VALUE(*bucket));
        }
        memcpy(BUCKET_VALUE(*bucket), data, map->type_size);
    }
}

void hashmap_delete(struct hashmap *map, const char *key, int key_len)
{
    assert(map != NULL);
    assert(key != NULL);
    assert(key_len > 0);

    const unsigned int hash = fnv1a_hash(key, key_len);
    int i = 0;
    void **bucket = NULL;
    do {
        const int index = (hash + i * i) % map->capacity;
        i++;
        bucket = &map->buckets[index];
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
        map->size--;
    }
}

void *hashmap_get(struct hashmap *map, const char *key, int key_len)
{
    assert(map != NULL);
    assert(key != NULL);
    assert(key_len > 0);

    if (map->buckets == NULL) {
        return NULL;
    }

    const unsigned int hash = fnv1a_hash(key, key_len);
    int i = 0;
    void *bucket = NULL;
    do {
        const int index = (hash + i * i) % map->capacity;
        i++;
        bucket = map->buckets[index];
        if (bucket != NULL 
            && strcmp(*BUCKET_KEY(bucket), key) == 0) {
            break;
        }
    } while(bucket != NULL);
    
    // Key exists
    if (bucket != NULL) {
        return BUCKET_VALUE(bucket);
    } else {
        return NULL;
    }
}
