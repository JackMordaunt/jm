#+build darwin
package shell

import "base:intrinsics"

foreign import block_system "system:System"

// Shared by the scroll and title-bar event monitors. Declare the foreign
// global once: duplicate LLVM globals would rename one at link time.
@(private)
foreign block_system {
	_NSConcreteGlobalBlock: intrinsics.objc_class
}
