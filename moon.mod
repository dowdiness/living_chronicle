// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "dowdiness/living_chronicle"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/dowdiness/living_chronicle"

license = "Apache-2.0"

keywords = [ ]

preferred_target = "wasm-gc"

description = ""

import {
  "dowdiness/event-graph-walker@0.6.0",
}
