#include "lexer.hpp"

namespace Lang {

static const std::unordered_map<std::string_view, Token::Kind> KEYWORD_MAP = {
    { "func", Token::Kind::FuncKeyword },
};

static bool is_number(char c) {
    return c >= '0' && c <= '9';
}

static bool is_alpha(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

static bool is_ident(char c) {
    return c == '_' || is_alpha(c) || is_number(c);
}

static bool is_whitespace(char c) {
    return c == '\n' || c == ' ' || c == '\t';
}

std::string_view Token::to_string(CompileContext& ctx) {
    const std::string_view src = ctx.get_source();
    return std::string_view{ src.begin() + start, src.begin() + end };
}

Token Lexer::get_token(size_t token_idx) {
    return tokens.at(token_idx);
}

std::span<Token> Lexer::span_tokens(size_t start, size_t end) {
    return std::span<Token>(tokens).subspan(start, end);
}

void Lexer::tokenize() {

}

void Lexer::ident() {
    const size_t start = index;
    next_while(is_ident);
    const size_t end = index;
    const Token token = {
        .kind = Token::Kind::Identifier,
        .start = start,
        .end = end,
    };
    tokens.push_back(token);
}

void Lexer::int_literal() {
    const size_t start = index;
    next_while(is_number);
    const size_t end = index;
    const Token token = {
        .kind = Token::Kind::IntLiteral,
        .start = start,
        .end = end,
    };
    tokens.push_back(token);
}

void Lexer::special() {

}

char Lexer::peek() const {
    return ctx.get_source().at(index);
}

char Lexer::next() {
    return ctx.get_source().at(index++);
}

void Lexer::next_while(std::function<bool(char)> func) {
    while (func(peek())) {
        next();
    }
}

} // namespace Lang
