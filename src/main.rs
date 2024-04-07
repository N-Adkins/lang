#![allow(unused)]

use lexer::Lexer;

mod lexer;
mod parser;
mod token;

fn main() {
    let test_source = "test _klas 721317 () (){} tes}";
    let mut lexer = Lexer::new(test_source);
    lexer.process();
    println!("{lexer:#?}");
}
