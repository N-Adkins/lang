#ifndef LANG_LEXER_H
#define LANG_LEXER_H

#include <stdint.h>
#include "../error.h"

enum token_tag {
    TOKEN_EOF,
    TOKEN_KEYWORD_VAR,
    TOKEN_IDENT,
    TOKEN_LPAREN,
    TOKEN_RPAREN,
    TOKEN_LCURLY,
    TOKEN_RCURLY,
    TOKEN_COLON,
    TOKEN_SEMICOLON,
};

struct token {
    enum token_tag tag;
    uint32_t start;
    uint32_t end;
};

struct lexer {
    struct error_ctx *err_ctx;
    struct source_info *source;
    uint32_t index;
};

struct lexer lexer_init(struct error_ctx *err_ctx, struct source_info *source);
void lexer_next(struct lexer *lexer, struct token *token);

#endif
