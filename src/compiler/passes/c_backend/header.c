/*
 *  This code was generated by the compiler of N-Adkins
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int64_t __Lang_int;
typedef uint8_t __Lang_bool;
typedef void __Lang_void;

void __Lang_RuntimeErrorInternal(const char *msg)
{
    fputs(msg, stderr);
    exit(EXIT_FAILURE);
}
#define __Lang_RuntimeError(msg) __Lang_RuntimeErrorInternal(msg)

void *__Lang_AllocInternal(size_t bytes) 
{
    void *data = malloc(bytes);
    if (data == NULL) {
        __Lang_RuntimeError("OutOfMemory");
    }
    return data;
}
#define __Lang_Alloc(T, amount) (T*)__Lang_AllocInternal(sizeof(T) * (amount))

void __Lang_FreeInternal(void *ptr)
{
    free(ptr);
}
#define __Lang_Free(ptr) __Lang_FreeInternal((ptr))

typedef struct __Lang_Object
{
    struct __Lang_Object *next;
    uint64_t ref_count;
} __Lang_Object;

typedef struct
{
    __Lang_Object *records;
} __Lang_GC;
static __Lang_GC __Lang_GC_Instance{
    .records = NULL,
};

void __Lang_GC_Cleanup() 
{
    __Lang_Object *prev = NULL;
    __Lang_Object *iter = __Lang_GC_Instance.records;
    while (iter != NULL) {
        if (iter->ref_count == 0) {
            __Lang_Object *to_destroy = iter;
            iter = iter->next;
            // object specific free
            __Lang_Free(to_destroy);
        } else {
            prev = iter;
            iter = iter->next;
        }
    }
}

__Lang_Object *__Lang_GenObject() 
{
    __Lang_Object *obj = __Lang_Alloc(__Lang_Object, 1);
    obj->next = __Lang_GC_Instance.records;
    obj->ref_count = 0;
    __Lang_GC_Instance.records = obj;
    return obj;
}
