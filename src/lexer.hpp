#pragma once

#include <functional>
#include <span>
#include <string_view>
#include <vector>
#include "context.hpp"

namespace Lang {

struct Token {
    enum class Kind {
        Invalid,
        Identifier,
        IntLiteral,
        FuncKeyword,
        Semicolon,
        Colon,
        Comma,
        Period,
        LCurly,
        RCurly,
        LParen,
        RParen,
        Plus,
        Minus,
        Asterisk,
        Slash,
        Equals,
    };

    Kind kind;
    size_t start;
    size_t end;

    std::string_view to_string(CompileContext& ctx);
};

class Lexer {
public:
    Lexer(CompileContext& ctx)
        : ctx(ctx) {}

    Token get_token(size_t token_idx) const;
    std::span<Token> span_tokens(size_t start, size_t end);
    std::span<Token> all_tokens();
    void tokenize();

private:
    void ident();
    void int_literal();
    void special();

    char peek() const;
    char next();

    void next_while(std::function<bool(char)> func);

    std::vector<Token> tokens;
    CompileContext& ctx;
    size_t index = 0;
};

} // namespace Lang 
