#include "lexer.hpp"

#include <format>

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

Token Lexer::get_token(size_t token_idx) const {
    return tokens.at(token_idx);
}

std::span<Token> Lexer::span_tokens(size_t start, size_t end) {
    return std::span<Token>(tokens).subspan(start, end);
}

std::span<Token> Lexer::all_tokens() {
    return tokens;
}

void Lexer::tokenize() {
    const size_t source_len = ctx.get_source().length();
    while (index < source_len) {
        next_while(is_whitespace);
        const char current = peek();
        if (is_alpha(current) || current == '_') {
            ident();
        } else if (is_number(current)) {
            int_literal();
        } else {
            special();
        }
    }
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
    char current = next();
    const size_t start = index;
    Token::Kind kind;
    switch (current) {
    case ';': kind = Token::Kind::Semicolon; break;
    case ':': kind = Token::Kind::Colon; break;
    case ',': kind = Token::Kind::Comma; break;
    case '.': kind = Token::Kind::Period; break;
    case '{': kind = Token::Kind::LCurly; break;
    case '}': kind = Token::Kind::RCurly; break;
    case '(': kind = Token::Kind::LParen; break;
    case ')': kind = Token::Kind::RParen; break;
    case '+': kind = Token::Kind::Plus; break;
    case '-': kind = Token::Kind::Minus; break;
    case '*': kind = Token::Kind::Asterisk; break;
    case '/': kind = Token::Kind::Slash; break;
    case '=': kind = Token::Kind::Equals; break;
    default:
        ctx.push_error(Error(std::format("Found invalid character '{}'", current), start));
        return;
    }
    const size_t end = index;
    const Token token = {
        .kind = kind,
        .start = start,
        .end = end,
    };
    tokens.push_back(token);
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
