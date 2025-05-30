#pragma once

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
    };

    Kind kind;
    int start;
    int end;

    std::string_view to_string(CompileContext& ctx);
};

class Lexer {
public:
    Lexer(CompileContext& ctx)
        : ctx(ctx) {}

    void tokenize();
    Token get_token(int index);
    std::span<Token> span_tokens(int start, int end);

private:
    

    std::vector<Token> tokens;
    CompileContext& ctx;
};

} // namespace Lang 
