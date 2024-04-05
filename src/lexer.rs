use std::collections::VecDeque;
use crate::token::{Token, TokenTag};

#[derive(Debug)]
struct Lexer<'a> {
    source: &'a str,
    index: usize,
    tokens: VecDeque<Token<'a>>,
}

impl<'a> Lexer<'a> {
    pub fn new(source: &'a str) -> Self {
        Self {
            source,
            index: 0,
            tokens: VecDeque::new(),
        }
    }

    pub fn peek(&self) -> Option<&Token<'a>> {
        self.tokens.front()
    }

    pub fn next(&mut self) -> Option<Token<'a>> {
        self.tokens.pop_front()
    }

    pub fn process(&mut self) {
        while self.peek_char().is_some() { 
            self.tokenize_next();
        }
    }

    fn tokenize_next(&mut self) {
        let c = self.peek_char().unwrap();
        if c.is_numeric() {
            self.tokenize_number();
        } else if c.is_alphabetic() || c == '_' {
            self.tokenize_identifier();
        } else {
            self.tokenize_special();
        }
    }

    fn tokenize_number(&mut self) {
        let raw = self.tokenize_while(|c| c.is_numeric());
        self.tokens.push_back(Token{
            tag: TokenTag::Number,
            raw,
        })
    }

    fn tokenize_identifier(&mut self) {
        let raw = self.tokenize_while(|c| c.is_numeric());
        let token = Token{
            tag: TokenTag::Number,
            raw,
        };
        self.tokens.push_back(token);
    }

    fn tokenize_while(&mut self, func: impl Fn(char) -> bool) -> &str {
        let start = self.index;
        while let Some(c) = self.peek_char() {
            if !func(c) {
                break
            }
            self.eat_char();
        }
        let end = self.index;
        return &self.source[start..end];
    }

    fn peek_char(&self) -> Option<char> {
        self.source.chars().nth(self.index)
    }

    fn eat_char(&mut self) -> Option<char> {
        let c = self.source.chars().nth(self.index);
        self.index += 1;
        c
    }
}
