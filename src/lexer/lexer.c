#include "lexer.h"

#include <assert.h>
#include <stdlib.h>

#define GEN_TOKEN_STRING(token) \
    #token,

const char *token_tag_tostring[] = {
    FOREACH_TOKEN(GEN_TOKEN_STRING)
};

static bool is_whitespace(char c)
{
    return c == ' ' || c == '\n' || c == '\t';
}

static bool is_number(char c)
{
    return c >= '0' && c <= '9';
}

static bool is_alpha(char c)
{ 
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

static bool is_ident(char c)
{
    return is_number(c) || is_alpha(c) || c == '_';
}

static void tokenize_ident(struct lexer *lexer, struct token *token)
{
    assert(lexer != NULL);
    assert(token != NULL);

    const int start = lexer->index;
    while (lexer->index < lexer->source->len && is_ident(lexer->source->raw[lexer->index])) {
        lexer->index++;
    }
    const int end = lexer->index;

    const enum token_tag tag = TOKEN_IDENT;

    *token = (struct token) {
        .tag = tag,
        .start = start,
        .end = end,
    };
}

static void tokenize_num(struct lexer *lexer, struct token *token)
{
    assert(lexer != NULL);
    assert(token != NULL);

    const int start = lexer->index;
    while (lexer->index < lexer->source->len && is_number(lexer->source->raw[lexer->index])) {
        lexer->index++;
    }
    const int end = lexer->index;

    const enum token_tag tag = TOKEN_INT_LIT;

    *token = (struct token) {
        .tag = tag,
        .start = start,
        .end = end,
    };
}

static void tokenize_misc(struct lexer *lexer, struct token *token)
{
    assert(lexer != NULL);
    assert(token != NULL);

    const int start = lexer->index;
    const char next_c = lexer->source->raw[lexer->index++];
    
    enum token_tag tag = TOKEN_ERROR;
    switch (next_c) {
    case '(': tag = TOKEN_LPAREN; break;
    case ')': tag = TOKEN_RPAREN; break;
    case '{': tag = TOKEN_LCURLY; break;
    case '}': tag = TOKEN_RCURLY; break;
    case ':': tag = TOKEN_COLON; break;
    case ';': tag = TOKEN_SEMICOLON; break;
    case ',': tag = TOKEN_COMMA; break;
    default:
        error_ctx_push(lexer->err_ctx, lexer->source, "Found illegal character '%c'", next_c);
    }

    const int end = lexer->index;

    *token = (struct token) {
        .tag = tag,
        .start = start,
        .end = end,
    };
}

struct lexer lexer_init(struct error_ctx *err_ctx, struct source_info *source)
{
    return (struct lexer) {
        .err_ctx = err_ctx,
        .source = source,
        .index = 0,
    };
}

void skip_whitespace(struct lexer *lexer)
{
    while (lexer->index < lexer->source->len && is_whitespace(lexer->source->raw[lexer->index])) {
        lexer->index++;
    }
}

void lexer_next(struct lexer *lexer, struct token *token)
{
    assert(lexer != NULL);
    assert(token != NULL);

    skip_whitespace(lexer);

    if (lexer->index >= lexer->source->len) {
        *token = (struct token) {
            .tag = TOKEN_EOF,
            .start = lexer->source->len - 1,
            .end = lexer->source->len,
        };
        return;
    }

    const char next = lexer->source->raw[lexer->index];
    if (is_number(next)) {
        tokenize_num(lexer, token);
        return;
    } else if (is_ident(next)) {
        tokenize_ident(lexer, token);
        return;
    } else {
        tokenize_misc(lexer, token);
        return;
    }
}
