#ifndef LANG_PARSER_AST_H
#define LANG_PARSER_AST_H

#include "error.h"
#include "../containers/list.h"

#define AST_STRING_LEN 128

#define FOREACH_AST_NODE(NODE) \
    NODE(MODULE) \
    NODE(FUNC_DECL) \
    NODE(BLOCK) \
    NODE(VAR_DECL) \
    NODE(VAR_GET) \
    NODE(INT_LIT) \
    NODE(TYPE_NAME)

#define GEN_AST_ENUM(node) \
    AST_##node,

enum ast_tag {
    FOREACH_AST_NODE(GEN_AST_ENUM)
};

extern const char *ast_tag_tostring[];

struct ast_node {
    char string[AST_STRING_LEN];
    struct dynarray children;
    const struct source_info *source;
    int number;
    int source_index;
    enum ast_tag tag;
};

struct ast_node *ast_init(void);
void ast_deinit(struct ast_node *node);
void ast_dump(struct ast_node *root);

#endif
