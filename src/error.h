#ifndef LANG_ERROR_H
#define LANG_ERROR_H

#include <stdint.h>

struct source_info {
    char filename[512];
    const char *source;
};

struct error {
    char msg[512];
    const struct source_info *source;
};

struct error_context {
    struct error *errors;
    uint32_t size;
    uint32_t capacity;
};

struct error_context init_error_ctx(void);
void deinit_error_ctx(struct error_context *ctx);
void push_error(struct error_context *ctx, const struct source_info *source, const char *msg, ...);

#endif
