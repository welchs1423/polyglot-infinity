// build.zig - Zig 0.13 build script for wasm-zig/src/finance.zig
//
// Target  : wasm32-freestanding (no OS, no libc)
// Output  : zig-out/bin/finance.wasm
// Usage   : zig build            -- Debug (default for development)
//           zig build -Drelease  -- ReleaseSmall (preferred_optimize_mode below)
//
// Exported functions are driven by the `export` keyword on each function in
// finance.zig; -rdynamic keeps all of them visible to the browser's
// WebAssembly.instantiate API.
//
// Memory: a single Wasm page (64 KiB) is sufficient for the finance.zig
// stack usage (mcVaR95 uses a 2000-element f64 array = 16 KiB).

const std = @import("std");

pub fn build(b: *std.Build) void {
    // Default optimisation: ReleaseSmall produces the smallest .wasm file,
    // which minimises browser initial-load latency.
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    // Hard-code the target to wasm32-freestanding.
    // standardTargetOptions is intentionally NOT used here because this
    // build file is exclusively for the browser WASM artifact.
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const exe = b.addExecutable(.{
        .name = "finance",
        .root_source_file = b.path("src/finance.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Disable the default entry point: this is a library, not a program.
    exe.entry = .disabled;

    // Keep all symbols marked `export` in finance.zig visible to the browser
    // via WebAssembly.Instance.exports.
    exe.rdynamic = true;

    b.installArtifact(exe);
}
