// Package accesskit binds accesskit-c (github.com/AccessKit/accesskit-c,
// release 0.23.1, fetched by `just accesskit`): one C API over the
// platforms' accessibility protocols, which the AccessKit README lists as
// AT-SPI2 on Linux and the BSDs, UI Automation on Windows and
// NSAccessibility on macOS. A toolkit pushes a tree
// of nodes, each with a role, a label, bounds, states and the actions it
// takes; the adapter keeps the tree and hands actions back from the
// assistive technology's thread. tree.odin builds that tree from a
// ui.Frame's semantic nodes; ui/sdl owns the adapter and the loop.
//
// Only the Linux adapter is bound so far. The binding itself (api.odin)
// is linked on Linux only, so this package type-checks everywhere and
// links nowhere else.
package accesskit
