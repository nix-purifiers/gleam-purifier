import gleam/string
import gleam/io

pub fn main() {
  io.println("locked Gleam")
}

pub fn greet(name: String) -> String {
  string.uppercase("Hola, " <> name)
}
