#ifndef LANG_PASSES_SYMBOL_H
#define LANG_PASSES_SYMBOL_H

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
    type_id *child;
    int child_count;
    int child_capacity;
    enum type_tag tag;
};

struct type type_init(enum type_tag tag);
void type_deinit(struct type *type);
void type_push_child(struct type *parent, type_id child);

struct type_list {
    struct type *types; 
    int count;
    int capacity;
};

struct type_list type_list_init(void);
void type_list_deinit(struct type_list *list);
struct type *type_list_get(struct type_list *list, type_id id);
type_id type_list_push(struct type_list *list, struct type type);

typedef int symbol_id;

struct symbol {
    char name[128];
    type_id type;
};

struct symbol_list {
    struct symbol *symbols;
    int count;
    int capacity;
};

typedef int scope_id;

struct scope {
    struct symbol_table *table;
    symbol_id *symbols;
    scope_id parent;
    int count;
    int capacity;
};

struct scope_list {
    struct scope *scopes;
    int count;
    int capacity;
};

struct symbol_table {
    struct scope_list scopes;
    struct symbol_list symbols;
    struct type_list types;
};

#endif
