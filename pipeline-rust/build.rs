/*
 * build.rs — compile core-cpp/src/matrix.cpp as a static archive and
 * instruct Cargo to link it into the pipeline-rust binary.
 *
 * The cc crate invokes the system C++ compiler (g++ on Linux, clang++ on
 * macOS) with the flags listed below.  No shared-library installation is
 * required; everything is baked into the final binary at link time.
 *
 * Linking order matters: libstdc++ (or libc++) must be listed after the
 * static archive so the linker resolves C++ runtime symbols correctly.
 */

fn main() {
    cc::Build::new()
        .cpp(true)
        .opt_level(3)
        .flag("-std=c++17")
        .flag("-fPIC")
        .flag("-Wall")
        .flag("-Wextra")
        /* Suppress pedantic warnings that fire on C headers included from C++. */
        .flag("-Wno-unused-parameter")
        .file("../core-cpp/src/matrix.cpp")
        .compile("cppmatrix");

    /* The compiled archive is already linked by cc::Build::compile().
     * We still need the C++ standard library for std::memset / std::malloc. */
    println!("cargo:rustc-link-lib=stdc++");

    /* Re-run this script if the C++ source or header changes. */
    println!("cargo:rerun-if-changed=../core-cpp/src/matrix.cpp");
    println!("cargo:rerun-if-changed=../core-cpp/src/matrix.h");
}
