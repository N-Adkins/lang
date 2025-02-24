#ifndef LANG_PARSER_PARSER_H
#define LANG_PARSER_PARSER_H

#include "../error.h"
#include "../lexer.h"
#include "ast.h"

struct parser {
    const struct source_info *source;
    struct error_ctx *err_ctx;
    struct lexer *lexer;
    struct token previous;
    struct token current;
};

struct ast_node *parser_parse(struct parser *parser);

#endif
