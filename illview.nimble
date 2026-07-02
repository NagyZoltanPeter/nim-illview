# Package

version       = "0.1.0"
author        = "Zoltan Peter Nagy"
description   = "Retained-mode, TurboVision-inspired TUI widget framework on a vendored illwill + chronos"
license       = "MIT"
srcDir        = "src"
skipDirs      = @["tests", "examples", "docs"]

# Dependencies

requires "nim >= 2.0.0"
requires "chronos >= 4.0.0"
# nim-brokers is bound in Phase 6 (not in the nimble registry; see
# docs/DESIGN-DEVIATIONS.md). Phases 1-5 use the StubBus.

task test, "Run the test suite":
  exec "nim c -r --mm:orc --hints:off tests/test_decoder.nim"
