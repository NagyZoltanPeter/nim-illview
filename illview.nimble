# Package

version       = "0.1.0"
author        = "Zoltan Peter Nagy"
description   = "Retained-mode, TurboVision-inspired TUI widget framework on a vendored illwill + chronos"
license       = "MIT"
srcDir        = "src"
skipDirs      = @["tests", "examples", "docs"]

# Dependencies

requires "nim >= 2.2.4"
requires "chronos >= 4.0.0"
requires "brokers >= 3.3.0" # nim-brokers; bus_brokers (Phase 6) + instance-ctx vocab (Phase 12)

task test, "Run the test suite":
  mkDir "build/tests"
  for t in ["test_decoder", "test_layout", "test_render_snapshot",
            "test_routing", "test_widgets", "test_mount", "test_bus_brokers",
            "test_bindings", "test_ctx_vocab", "test_scrollbar", "test_scroller",
            "test_splitter", "test_desktop", "test_hotkey", "test_menu"]:
    exec "nim c -r --mm:orc --hints:off -o:build/tests/" & t & " tests/" & t & ".nim"

task examples, "Build all examples (POSIX)":
  mkDir "build/examples"
  for ex in ["ex00_echo", "ex01_loop", "ex02_windows", "ex03_layout",
             "ex04_widgets_gallery", "ex05_declarative", "ex06_netviz", "ex07_styling",
             "ex09_bindings", "ex10_instance_ctx", "ex11_scroller",
             "ex12_splitter"]:
    exec "nim c --mm:orc --hints:off -o:build/examples/" & ex & " examples/" & ex & ".nim"

task screenshots, "Regenerate the README screenshots (docs/assets/*.svg)":
  mkDir "docs/assets"
  mkDir "build"
  exec "nim c -r --mm:orc --hints:off -o:build/screenshots tools/screenshots.nim"
