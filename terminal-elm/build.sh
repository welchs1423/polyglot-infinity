#!/bin/sh
set -e

if ! command -v elm > /dev/null 2>&1; then
    echo "elm not found. Install via npm: npm install -g elm"
    echo "or download from https://github.com/elm/compiler/releases"
    exit 1
fi

elm make src/Main.elm --output=elm.js --optimize
echo "build complete: elm.js"
