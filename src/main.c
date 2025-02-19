#include "error.h"

int main(void)
{
    struct error_context err_ctx = init_error_ctx();
    deinit_error_ctx(&err_ctx);
    return 0;
}
