#include "error.h"

int main(void)
{
    struct error_ctx err_ctx = error_ctx_init();
    error_ctx_deinit(&err_ctx);
    return 0;
}
