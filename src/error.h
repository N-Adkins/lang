#ifndef LANG_ERROR_H
#define LANG_ERROR_H

#include <stdbool.h>
#include <stdint.h>

// Descriptor for a source file of code
struct source_info {
    char filename[512];
    const char *raw;
    uint64_t len;
};

struct error {
    char msg[512];
    const struct source_info *source;
};

// Maintains a list of compilation errors to allow more than one to be
// captured at a time
struct error_ctx {
    struct error *errors;
    uint32_t size;
    uint32_t capacity;
};

struct error_ctx error_ctx_init(void);
void error_ctx_deinit(struct error_ctx *ctx);
void error_ctx_push(struct error_ctx *ctx, const struct source_info *source, const char *msg, ...);
bool error_ctx_isempty(const struct error_ctx *ctx);
void error_ctx_dump(const struct error_ctx *ctx);

#endif
