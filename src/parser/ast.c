#include "ast.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define GEN_NODE_STRING(node) \
    #node,

const char *ast_tag_tostring[] = {
    FOREACH_AST_NODE(GEN_NODE_STRING) 
};

static void ast_destructor(void *ptr)
{
    ast_deinit(*(struct ast_node**)ptr);
}

static char *ast_sprintf(char *buffer, struct ast_node *node)
{
    buffer += sprintf(buffer,
        "{\"tag\":\"%s\",\"string\":\"%s\",\"number\":%d,\"source_idx\":%d,\"children\":[",
        ast_tag_tostring[node->tag], node->string, node->number, node->source_index);
    
    for (int i = 0; i < node->children.size; i++) {
        struct ast_node *child = *(struct ast_node **)dynarray_get(&node->children, i);
        buffer = ast_sprintf(buffer, child);
        if (i < node->children.size - 1) {
            buffer += sprintf(buffer, ",");
        }
    }

    buffer += sprintf(buffer, "]}");

    return buffer;
}

struct ast_node *ast_init(void)
{
    struct ast_node *node = malloc(sizeof(struct ast_node));
    if (node == NULL) {
        fprintf(stderr, "OOM\n");
        return NULL;
    }

    *node = (struct ast_node) {
        .number = 0,
        .children = dynarray_init(sizeof(struct ast_node *), ast_destructor),
    };

    memset(&node->string[0], '\0', AST_STRING_LEN);
    
    return node;
}

void ast_deinit(struct ast_node *node)
{
    assert(node != NULL);
    dynarray_deinit(&node->children);
    free(node);
}

void ast_dump(struct ast_node *root)
{
    char buffer[0xFFFF]; // Should work for now
    ast_sprintf(buffer, root);
    printf("%s\n", buffer);
}
