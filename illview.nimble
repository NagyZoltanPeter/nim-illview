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
  for t in ["test_decoder", "test_layout", "test_render_snapshot", "test_routing"]:
    exec "nim c -r --mm:orc --hints:off tests/" & t & ".nim"

task examples, "Build all examples (POSIX)":
  for ex in ["ex00_echo", "ex01_loop", "ex02_windows", "ex03_layout"]:
    exec "nim c --mm:orc --hints:off examples/" & ex & ".nim"
