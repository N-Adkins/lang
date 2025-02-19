#include "lexer.h"

#define GEN_TOKEN_STRING(token) \
    #token,

const char *token_tag_tostring[] = {
    FOREACH_TOKEN(GEN_TOKEN_STRING)
};

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
    const uint32_t start = lexer->index;
    while (lexer->index < lexer->source->len && is_ident(lexer->source->raw[lexer->index])) {
        lexer->index++;
    }
    const uint32_t end = lexer->index;

    enum token_tag tag = TOKEN_IDENT;

    *token = (struct token) {
        .tag = tag,
        .start = start,
        .end = end,
    };
}

static void tokenize_misc(struct lexer *lexer, struct token *token)
{
    const uint32_t start = lexer->index;
    const char next_c = lexer->source->raw[lexer->index++];
    
    enum token_tag tag = TOKEN_EOF;
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

    const uint32_t end = lexer->index;

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

void lexer_next(struct lexer *lexer, struct token *token)
{
    if (lexer->index >= lexer->source->len) {
        *token = (struct token) {
            .tag = TOKEN_EOF,
            .start = lexer->source->len - 1,
            .end = lexer->source->len,
        };
        return;
    }

    const char next = lexer->source->raw[lexer->index];
    if (is_ident(next)) {
        tokenize_ident(lexer, token);
    } else {
        tokenize_misc(lexer, token);
    }
}
