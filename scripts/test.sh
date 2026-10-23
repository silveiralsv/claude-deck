#!/bin/sh
# Runs every check: the hook.sh smoke test and the Swift tests.
set -e
cd "$(dirname "$0")/.."
sh scripts/test-hook.sh
if xcode-select -p | grep -q CommandLineTools; then
  # Command Line Tools keep swift-testing outside the default search paths. Xcode doesn't need this.
  F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
  L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
  swift test -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L
else
  swift test
fi
