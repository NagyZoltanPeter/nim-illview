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
requires "brokers >= 3.4.0" # nim-brokers; bus_brokers (Phase 6) + listenIt/onSignalIt handler sugar (per-type since 3.4.0)
requires "chronicles" # examples/ex14_logpane dynamic sink

const testFiles = ["test_decoder", "test_layout", "test_render_snapshot",
                   "test_routing", "test_widgets", "test_mount", "test_bus_brokers",
                   "test_bindings", "test_ctx_vocab", "test_scrollbar", "test_scroller",
                   "test_splitter", "test_desktop", "test_hotkey", "test_menu",
                   "test_validators", "test_dialogs", "test_tree", "test_app",
                   "test_theme", "test_tabview"]

const exampleFiles = ["ex00_echo", "ex01_loop", "ex02_windows", "ex03_layout",
                      "ex04_widgets_gallery", "ex05_declarative", "ex06_netviz",
                      "ex07_styling", "ex09_bindings", "ex10_instance_ctx",
                      "ex11_scroller", "ex12_splitter", "ex13_showcase", "ex14_logpane",
                      "ex15_tabs"]

proc memoryManager(): string =
  ## ILLVIEW_MM=refc|orc selects the memory manager for `test`/`examples`
  ## (the CI matrix sets it); default orc.
  if existsEnv("ILLVIEW_MM"): getEnv("ILLVIEW_MM") else: "orc"

proc runTests(mm: string, extra = "", suffix = "") =
  mkDir "build/tests"
  for t in testFiles:
    exec "nim c -r --mm:" & mm & " " & extra & " --hints:off -o:build/tests/" &
         t & suffix & " tests/" & t & ".nim"

task test, "Run the test suite (ILLVIEW_MM=orc|refc, default orc)":
  runTests(memoryManager())

task testRefc, "Run the test suite under --mm:refc":
  runTests("refc", suffix = "_refc")

task testAsan, "Run the test suite under AddressSanitizer (orc + useMalloc)":
  runTests("orc", "-d:useMalloc --passC:\"-fsanitize=address -fno-omit-frame-pointer\" " &
                  "--passL:-fsanitize=address", suffix = "_asan")

task examples, "Build all examples (POSIX; ILLVIEW_MM=orc|refc)":
  mkDir "build/examples"
  for ex in exampleFiles:
    exec "nim c --mm:" & memoryManager() & " --hints:off -o:build/examples/" & ex &
         " examples/" & ex & ".nim"

task screenshots, "Regenerate the README screenshots (docs/assets/*.svg)":
  mkDir "docs/assets"
  mkDir "build"
  exec "nim c -r --mm:orc --hints:off -o:build/screenshots tools/screenshots.nim"
