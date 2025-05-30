#include "context.hpp"

namespace Lang {

void CompileContext::push_error(const Error& err) {
    errors.push_front(err);
}

bool CompileContext::has_errors() const {
    return !errors.empty();
}

std::string_view CompileContext::get_source() const {
    return source;
}

} // namespace Lang
