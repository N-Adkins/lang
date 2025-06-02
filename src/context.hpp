#pragma once

#include <deque>
#include <span>
#include <string>

namespace Lang {

struct Token;

struct Error {
    Error(const std::string& message, std::span<Token> tokens)
        : message(message), tokens(tokens) {}

    Error(const std::string& message, int index)
        : message(message), index(index) {}

    std::string message;
    std::span<Token> tokens;
    int index = -1; // This is only used for lexer errors, basically
};

class CompileContext {
public:
    CompileContext(const std::string& source)
        : source(source) {}

    void push_error(const Error& err);
    bool has_errors() const;
    std::string_view get_source() const;

private:
    std::string source;
    std::deque<Error> errors;
};

} // namespace Lang
