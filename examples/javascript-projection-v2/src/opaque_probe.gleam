import gleam/dynamic

@external(javascript, "./opaque_probe_ffi.mjs", "load")
pub fn load(name: String) -> dynamic.Dynamic
