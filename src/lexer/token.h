#ifndef LANG_LEXER_TOKEN_H
#define LANG_LEXER_TOKEN_H

#include <stdint.h>

enum token_tag {
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
};

int lexer_next(struct lexer *lexer, struct token *token);

#endif
