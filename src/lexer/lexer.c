#include "lexer.h"

#include <string.h>

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
    while (lexer->index < lexer->source->len && is_alpha(lexer->source->raw[lexer->index])) {
        lexer->index++;
    }
    const uint32_t end = lexer->index;

    enum token_tag tag = TOKEN_IDENT;
    if (strncmp(&lexer->source->raw[start], "var", end - start) == 0) {
        tag = TOKEN_KEYWORD_VAR;
    }

    *token = (struct token) {
        .tag = tag,
        .start = start,
        .end = end,
    };
}

static void tokenize_misc(struct lexer * lexer, struct token *token)
{

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
}
