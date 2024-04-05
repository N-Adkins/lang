use std::cell::OnceCell;

#[derive(Debug)]
enum Type {
    Number,
    String,
    Function(Vec<Type>, Box<Type>),
}

#[derive(Debug)]
struct TypedIdent {
    name: String,
    ident_type: Type,
}

#[derive(Debug)]
struct Block {
    statements: Vec<Statement>,
}

#[derive(Debug)]
enum Expression {
    IntLiteral(f64),
    StringLiteral(String),
    VariableGet(String),
    FunctionDecl(Vec<TypedIdent>, Type),
    Call(Box<Expression>, Vec<Expression>),
}

#[derive(Debug)]
enum Statement {
    VariableDecl(String, Type, Box<Expression>),
    Block(Block),
}
