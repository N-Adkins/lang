#include "parser.h"
#include "ast.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void parser_advance(struct parser *parser);
static bool parser_expect(struct parser *parser, enum token_tag tag, struct token *out_token);
static struct ast_node *parse_type(struct parser *parser);
static struct ast_node *parse_top_level(struct parser *parser);
static struct ast_node *parse_func_decl(struct parser *parser);
static struct ast_node *parse_stmt(struct parser *parser);
static struct ast_node *parse_block(struct parser *parser);
static struct ast_node *parse_var_decl(struct parser *parser);
static struct ast_node *parse_expr(struct parser *parser);
static struct ast_node *parse_var_get(struct parser *parser);
static struct ast_node *parse_int_lit(struct parser *parser);

static struct ast_node *node_from_token(const struct source_info *source, struct token token)
{
    assert(source != NULL);

    struct ast_node *node = malloc(sizeof(struct ast_node *));
    if (node == NULL) {
        fprintf(stderr, "OOM\n");
        return NULL;
    }

    ast_init(node);
    
    token_as_string(source, token, node->string);

    if (token.tag == TOKEN_INT_LIT) {
        node->number = atoi(node->string);
    }
    
    node->source = source;
    node->source_index = token.start;

    return node;
}

void parser_advance(struct parser *parser)
{
    assert(parser != NULL);

    parser->previous = parser->current;
    lexer_next(parser->lexer, &parser->current);
}

bool parser_expect(struct parser *parser, enum token_tag tag, struct token *out_token)
{
    assert(parser != NULL);

    if (parser->previous.tag == tag) {
        if (out_token != NULL) {
            *out_token = parser->previous;
        }
        parser_advance(parser);
        return true;
    }

    error_ctx_push(parser->err_ctx, parser->source, 
            "Expected token of type \"%s\", instead found token of type \"%s\"",
            token_tag_tostring[tag], token_tag_tostring[parser->previous.tag]);

    return false;
}

struct ast_node *parse_type(struct parser *parser)
{
    assert(parser != NULL);
    return NULL;
}

struct ast_node *parse_top_level(struct parser *parser)
{
    assert(parser != NULL);
    return NULL;
}

struct ast_node *parse_func_decl(struct parser *parser)
{
    assert(parser != NULL);
    return NULL;
}

struct ast_node *parse_stmt(struct parser *parser)
{
    assert(parser != NULL);
    return NULL;
}

struct ast_node *parse_block(struct parser *parser)
{
    assert(parser != NULL);

    struct token token;
    if (!parser_expect(parser, TOKEN_LCURLY, &token)) {
        return NULL;
    }



    return NULL;
}

struct ast_node *parse_var_decl(struct parser *parser)
{
    assert(parser != NULL);

    struct token token;
    if (!parser_expect(parser, TOKEN_KEYWORD_VAR, &token)) {
        return NULL;
    }

    if (!parser_expect(parser, TOKEN_IDENT, &token)) {
        return NULL;
    }

    struct ast_node *node = malloc(sizeof(struct ast_node *));
    if (node == NULL) {
        fprintf(stderr, "OOM\n");
        return NULL;
    }

    node->tag = AST_VAR_DECL;

    if (!parser_expect(parser, TOKEN_COLON, &token)) {
        goto FREE_NODE;
    }
    
    struct ast_node *type = parse_type(parser);
    if (type == NULL) {
        goto FREE_NODE;
    }

    if (!parser_expect(parser, TOKEN_EQUALS, &token)) {
        goto FREE_TYPE;
    }

    struct ast_node *expr = parse_expr(parser);
    if (expr == NULL) {
        goto FREE_TYPE;
    }

    ast_push_child(node, type);
    ast_push_child(node, expr);

    return node;

FREE_TYPE:;
    ast_deinit(type);
    free(type);
FREE_NODE:;
    ast_deinit(node);
    free(node);

    return NULL;
}

struct ast_node *parse_expr(struct parser *parser)
{
    assert(parser != NULL);
    
    switch (parser->previous.tag) {
    case TOKEN_IDENT:
        return parse_var_get(parser);
    case TOKEN_INT_LIT:
        return parse_int_lit(parser);
    default:
        break;
    }
    
    error_ctx_push(parser->err_ctx, parser->source, 
            "Expected expression instead found token of type \"%s\"",
            token_tag_tostring[parser->previous.tag]);

    return NULL;
}

struct ast_node *parse_var_get(struct parser *parser)
{
    assert(parser != NULL);
    
    struct token token;
    if (!parser_expect(parser, TOKEN_IDENT, &token)) {
        return NULL;
    }

    struct ast_node *node = node_from_token(parser->source, token);
    if (node == NULL) {
        return NULL;
    }
    node->tag = AST_VAR_GET;

    return node;
}

struct ast_node *parse_int_lit(struct parser *parser)
{
    assert(parser != NULL);

    struct token token;
    if (!parser_expect(parser, TOKEN_INT_LIT, &token)) {
        return NULL;
    }

    struct ast_node *node = node_from_token(parser->source, token);
    if (node == NULL) {
        return NULL;
    }
    node->tag = AST_INT_LIT;

    return node;
}

struct ast_node *parser_parse(struct parser *parser)
{
    assert(parser != NULL);
    
    struct ast_node *node = malloc(sizeof(struct ast_node *));
    if (node == NULL) {
        fprintf(stderr, "OOM\n");
        return NULL;
    }

    ast_init(node);
    node->tag = AST_MODULE;
    strcpy(node->string, parser->source->filename);
    
    // Initialize cached tokens
    parser_advance(parser);
    parser_advance(parser);
    
    while (parser->current.tag != TOKEN_EOF) {
        struct ast_node *top_level = parse_top_level(parser);
        if (top_level == NULL) {
            return NULL;
        }
        ast_push_child(node, top_level);
    }

    return node;
}
