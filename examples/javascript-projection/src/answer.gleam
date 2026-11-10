import gleam/string

pub fn answer(delta: Int) -> Int {
  string.length("******************************************") + delta
}
