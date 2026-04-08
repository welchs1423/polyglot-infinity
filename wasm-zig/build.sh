#!/usr/bin/env bash
#
# build.sh - compile wasm-zig/src/finance.zig to finance.wasm
#
# Usage:
#   ./build.sh               -- ReleaseSmall (default, smallest binary)
#   ./build.sh ReleaseFast   -- maximum runtime performance
#   ./build.sh ReleaseSafe   -- optimised with runtime safety checks
#   ./build.sh Debug         -- unoptimised, full debug info
#
# Output:
#   ./finance.wasm           -- final binary served by nginx to the browser
#
# Requirements:
#   zig 0.13.x must be on PATH (or set ZIG_BIN environment variable)
#
# Optimisation mode mapping (zig 0.13 -O flag values):
#   ReleaseSmall  -> smallest .wasm; recommended for production browser delivery
#   ReleaseFast   -> maximum throughput; larger binary
#   ReleaseSafe   -> optimised with runtime safety checks
#   Debug         -> unoptimised, full debug info

set -euo pipefail

ZIG_BIN="${ZIG_BIN:-zig}"
OPTIMIZE="${1:-ReleaseSmall}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[wasm-zig] compiler : $("$ZIG_BIN" version)"
echo "[wasm-zig] optimize : $OPTIMIZE"
echo "[wasm-zig] source   : $SCRIPT_DIR/src/finance.zig"

# Compile directly with zig build-exe (bypasses the build system for speed).
# Flags:
#   -target wasm32-freestanding   no OS ABI, no libc
#   -O <mode>                     optimisation level (see table above)
#   -fno-entry                    no _start / main required; pure library module
#   -rdynamic                     keep all `export`-annotated symbols in the binary
#   -femit-bin=finance.wasm       write the final .wasm to the nginx serve root
"$ZIG_BIN" build-exe \
    "$SCRIPT_DIR/src/finance.zig" \
    -target wasm32-freestanding \
    -O "$OPTIMIZE" \
    -fno-entry \
    -rdynamic \
    -femit-bin="$SCRIPT_DIR/finance.wasm"

WASM_SIZE=$(wc -c < "$SCRIPT_DIR/finance.wasm")
echo "[wasm-zig] output   : $SCRIPT_DIR/finance.wasm ($WASM_SIZE bytes)"
echo "[wasm-zig] build complete"
