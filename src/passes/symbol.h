#ifndef LANG_PASSES_SYMBOL_H
#define LANG_PASSES_SYMBOL_H

#include "../containers/list.h"
#include "../containers/hashmap.h"

#define FOREACH_TYPE(TYPE) \
    TYPE(VOID) \
    TYPE(INT) \
    TYPE(FUNCTION) \

#define GEN_TYPE_ENUM(type) \
    TYPE_##type,

enum type_tag {
    FOREACH_TYPE(GEN_TYPE_ENUM)
};

extern const char *type_tag_tostring[];

typedef int type_id;

struct type {
    struct dynarray child;
    enum type_tag tag;
};

struct type type_init(enum type_tag tag);
void type_deinit(struct type *type);

typedef int symbol_id;

struct symbol {
    char name[128];
    type_id type;
};

typedef int scope_id;

struct scope {
    struct hashmap symbols;
    struct symbol_table *table;
    scope_id parent;
    int count;
    int capacity;
};

struct symbol_table {
    struct dynarray scopes;
    struct dynarray symbols;
    struct dynarray types;
};

#endif
