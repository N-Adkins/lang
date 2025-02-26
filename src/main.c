#include "error.h"
#include "lexer.h"
#include "parser/ast.h"
#include "parser/parser.h"

#include <string.h>

int main(void)
{
    struct error_ctx err_ctx = error_ctx_init();
        
    const char *source_raw = "{ var test: idk = 0; }\n";
    struct source_info source = {
        .filename = "idk.test",
        .raw = source_raw,
        .len = strlen(source_raw),
    };

    struct lexer lexer = lexer_init(&err_ctx, &source);
    struct parser parser = {
        .lexer = &lexer,
        .source = &source,
        .err_ctx = &err_ctx,
    };
        
    struct ast_node *ast = parser_parse(&parser);
    
    if (ast != NULL) {
        ast_dump(ast);
        ast_deinit(ast);
    }

    if (!error_ctx_isempty(&err_ctx)) {
        goto DUMP_ERRORS;
    }

    error_ctx_deinit(&err_ctx);
    
    return 0;

DUMP_ERRORS:;
    error_ctx_dump(&err_ctx);
    error_ctx_deinit(&err_ctx);
    return 1;
}
