#include "lexer/lexer.h"
#include "error.h"

#include <stdio.h>
#include <string.h>

int main(void)
{
    struct error_ctx err_ctx = error_ctx_init();
        
    const char *source_raw = "idskdkdskdsk1283 832 % 89kd kd ksla kl ()() ();";
    struct source_info source = {
        .filename = "idk.test",
        .raw = source_raw,
        .len = strlen(source_raw),
    };

    struct lexer lexer = lexer_init(&err_ctx, &source);
    struct token token;
    do {
        lexer_next(&lexer, &token);
        printf("%s\n", token_tag_tostring[token.tag]);
    } while(token.tag != TOKEN_EOF);

    if (!error_ctx_isempty(&err_ctx)) {
        error_ctx_dump(&err_ctx);
    }

    error_ctx_deinit(&err_ctx);

    return 0;
}
