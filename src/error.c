#include "error.h"

#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

static void print_error(const struct error *err)
{
    assert(err != NULL);
    assert(err->msg != NULL);

    fprintf(stderr, "Compilation error: %s\n", err->msg);
}

struct error_ctx error_ctx_init(void)
{
    struct error_ctx ctx = {
        .errors = NULL,
        .size = 0,
        .capacity = 8,
    };

    ctx.errors = malloc(sizeof(struct error) * ctx.capacity);
    if (ctx.errors == NULL) {
        fprintf(stderr, "OOM\n");
    }

    return ctx;
}

void error_ctx_deinit(struct error_ctx *ctx)
{
    assert(ctx != NULL);
    assert(ctx->errors != NULL);

    free(ctx->errors);
}

void error_ctx_push(struct error_ctx *ctx, const struct source_info *source, const char *msg, ...)
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
        if (ctx->errors == NULL) {
            fprintf(stderr, "OOM\n");
            return;
        }
    }
    ctx->errors[ctx->size++] = err;
}

bool error_ctx_isempty(const struct error_ctx *ctx)
{
    assert(ctx != NULL);

    return ctx->size == 0;
}

void error_ctx_dump(const struct error_ctx *ctx)
{
    assert(ctx != NULL);
    assert(ctx->errors != NULL);

    for (int i = 0; i < ctx->size; i++) {
        print_error(&ctx->errors[i]);
    }
}
