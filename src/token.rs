#[derive(Debug)]
pub enum TokenTag {
    Identifier,
    Number,
    LParen,
    RParen,
    LCurly,
    RCurly,
    Comma,
    Semicolon,
}

#[derive(Debug)]
pub struct Token<'a> {
    pub tag: TokenTag,
    pub raw: &'a str,
}
