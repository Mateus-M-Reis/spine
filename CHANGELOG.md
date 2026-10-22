# Changelog

## [1.3.0] - 2026-10-22

Hardening release focused on reference conformance, CI, and lifecycle safety.

### Added

- GitHub Actions CI for LuaJIT, Lua 5.4, examples, benchmark budgets, and
  static analysis.
- Official Spine 4.2 reference fixtures for pose curves, looping and
  multi-track playback, IK, path constraints, physics channels, and
  transform-constraint mix timelines.
- Real-LÖVR smoke project and runner script (opt-in CI job for runners with a
  working Vulkan display).
- Transform-constraint local/relative modes, shear support, and applied/local
  bone transforms.
- Asset cache reference counting, skin-required bones/constraints, bounding
  boxes, sequences, and multi-page atlas support.
- Performance benchmark guard with allocation and CPU budgets.

### Fixed

- Bezier curves now use the Spine 4.2 sampled-curve approximation.
- Multi-track timelines use the correct FIRST/setup blend for properties not
  keyed by lower tracks.
- Path constraints handle one-bone tangent slots, chain advancement, closed
  paths, spacing modes, and chain scale.
- Physics limits scale independently on each skeleton axis.
- Cached assets are not released while still in use.
- Draw order and batch state are preserved across clipping and texture changes.
- Mesh UVs account for trimmed and rotated atlas regions.
- Ear clipping rejects reflex vertices on ear edges.

### Validation

- 204 headless checks on LuaJIT and Lua 5.4.
- Examples, all playground assets, and the benchmark budget pass.
- CI runs on every push and pull request.
