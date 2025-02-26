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

static char *ast_sprintf(char *buffer, struct ast_node *node)
{
    buffer += sprintf(buffer,
        "{\"tag\":\"%s\",\"string\":\"%s\",\"number\":%d,\"source_idx\":%d,\"children\":[",
        ast_tag_tostring[node->tag], node->string, node->number, node->source_index);
    
    for (int i = 0; i < node->child_count; i++) {
        buffer = ast_sprintf(buffer, node->child[i]);
        if (i < node->child_count - 1) {
            buffer += sprintf(buffer, ",");
        }
    }

    buffer += sprintf(buffer, "]}");

    return buffer;
}

void ast_init(struct ast_node *node)
{
    assert(node != NULL);

    *node = (struct ast_node) {
        .number = 0,
        .child = NULL,
        .child_count = 0,
        .child_capacity = 8,
    };

    memset(&node->string[0], '\0', AST_STRING_LEN);
}

void ast_deinit(struct ast_node *node)
{
    assert(node != NULL);
    for (int i = 0; i < node->child_count; i++) {
        ast_deinit(node->child[i]);
    }
    if (node->child != NULL) {
        free(node->child);
    }
    free(node);
}

void ast_push_child(struct ast_node *parent, struct ast_node *child)
{
    assert(parent != NULL);
    assert(child != NULL);

    if (parent->child_count == 0) {
        parent->child = malloc(parent->child_capacity * sizeof(struct ast_node *));
        if (parent->child == NULL) {
            fprintf(stderr, "OOM\n");
            return;
        }
    }

    if (parent->child_count >= parent->child_capacity) {
        parent->child_capacity *= 2;
        parent->child = realloc(parent->child, parent->child_capacity * sizeof(struct ast_node *));
        if (parent->child == NULL) {
            fprintf(stderr, "OOM\n");
            return;
        }
    }

    parent->child[parent->child_count++] = child;
}

void ast_dump(struct ast_node *root)
{
    char buffer[0xFFFF]; // Should work for now
    ast_sprintf(buffer, root);
    printf("%s\n", buffer);
}
