#include "error.h"

#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

struct error_context init_error_ctx(void)
{
    struct error_context ctx = {
        .errors = NULL,
        .size = 0,
        .capacity = 16,
    };

    ctx.errors = malloc(sizeof(struct error) * ctx.capacity);
    assert(ctx.errors != NULL);

    return ctx;
}


void deinit_error_ctx(struct error_context *ctx)
{
    assert(ctx != NULL);
    assert(ctx->errors != NULL);

    free(ctx->errors);
}

void push_error(struct error_context *ctx, const struct source_info *source, const char *msg, ...)
{
    assert(ctx != NULL);
    assert(source != NULL);
    assert(msg != NULL);

    va_list vargs;
    va_start(vargs, msg);

    struct error err;
    err.source = source;
    vsprintf(err.msg, msg, vargs);

    va_end(vargs);
    
    if (ctx->size >= ctx->capacity) {
        ctx->capacity *= 2;
        ctx->errors = realloc(ctx->errors, sizeof(struct error) * ctx->capacity);
        assert(ctx->errors != NULL);
    }
    ctx->errors[ctx->size++] = err;
}
