#include "lexer.hpp"

namespace Lang {

std::string_view Token::to_string(CompileContext& ctx) {
    auto src = ctx.get_source();
    return std::string_view{ src.begin() + start, src.begin() + end };
}

void Lexer::tokenize() {
    
}

Token Lexer::get_token(int index) {
    return tokens.at(index);
}

std::span<Token> Lexer::span_tokens(int start, int end) {
    return std::span<Token>(tokens).subspan(start, end);
}

} // namespace Lang
