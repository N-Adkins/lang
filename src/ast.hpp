#pragma once

#include <span>
#include "lexer.hpp"

namespace Lang {

using SymbolID = size_t;
using TypeID = size_t;

struct ASTNode {
    enum class Kind {
        IntConstant,
        VarDecl,
        VarGet,
    };

    union Value {
        struct {
            int value;
        } int_constant;

        struct {
            SymbolID symbol = -1;
            std::string name;
            TypeID type;
            ASTNode* expr;
        } var_decl;

        struct {
            SymbolID symbol = -1;
            std::string name;
        } var_get;

        ~Value() {}
    };

    Kind kind;
    Value value = {}; 
    std::span<Token> tokens;

    ~ASTNode() {
        switch (kind) {
        case Kind::IntConstant: break;
        case Kind::VarDecl:
            value.var_decl.name.~basic_string();
            delete value.var_decl.expr;
            break;
        case Kind::VarGet:
            value.var_get.name.~basic_string();
            break;
        }
    }
};

} // namespace Lang
