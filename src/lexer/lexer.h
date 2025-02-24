#ifndef LANG_LEXER_H
#define LANG_LEXER_H

#include "../error.h"

#define FOREACH_TOKEN(TOKEN) \
    TOKEN(EOF) \
    TOKEN(ERROR) \
    TOKEN(KEYWORD_VAR) \
    TOKEN(IDENT) \
    TOKEN(INT_LIT) \
    TOKEN(LPAREN) \
    TOKEN(RPAREN) \
    TOKEN(LCURLY) \
    TOKEN(RCURLY) \
    TOKEN(COLON) \
    TOKEN(SEMICOLON) \
    TOKEN(COMMA)

#define GEN_TOKEN_ENUM(token) \
    TOKEN_##token,

enum token_tag {
    FOREACH_TOKEN(GEN_TOKEN_ENUM)
};

extern const char *token_tag_tostring[];

struct token {
    enum token_tag tag;
    int start;
    int end;
};

struct lexer {
    struct error_ctx *err_ctx;
    struct source_info *source;
    int index;
};

struct lexer lexer_init(struct error_ctx *err_ctx, struct source_info *source);
void lexer_next(struct lexer *lexer, struct token *token);
void lexer_dump(struct lexer *lexer);

#endif
