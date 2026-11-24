fn main() {
    let target = std::env::var("TARGET").unwrap_or_default();
    if target.contains("windows-msvc") {
        let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
        let def_path = format!("{}\\exports.def", manifest_dir);
        println!("cargo:rustc-cdylib-link-arg=/DEF:{}", def_path);
        println!("cargo:rerun-if-changed=exports.def");
    }
}
