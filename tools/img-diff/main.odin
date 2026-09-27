// img-diff reports whether two PNGs are pixel-identical and, if not,
// where — as text, so checking whether an edit changed the render (and
// roughly what moved) costs no vision tokens unless something actually
// did and the change is worth a closer look.
//
//	img-diff before.png after.png
//	img-diff before.png after.png -tile 16
//	img-diff before.png after.png -out diff.png    also writes a highlight
package main

import "core:fmt"
import "core:os"
import "core:strconv"

import "jm:ui/render"

main :: proc() {
	if len(os.args) < 3 {
		fmt.eprintln("usage: img-diff <before.png> <after.png> [-tile N] [-out diff.png]")
		os.exit(2)
	}
	a_path, b_path := os.args[1], os.args[2]
	tile := 32
	out := ""
	args := os.args[3:]
	for i := 0; i < len(args); i += 1 {
		switch args[i] {
		case "-tile":
			i += 1
			if i >= len(args) {
				fmt.eprintln("-tile needs a value")
				os.exit(2)
			}
			n, ok := strconv.parse_int(args[i])
			if !ok || n <= 0 {
				fmt.eprintfln("-tile: not a positive integer: %s", args[i])
				os.exit(2)
			}
			tile = n
		case "-out":
			i += 1
			if i >= len(args) {
				fmt.eprintln("-out needs a path")
				os.exit(2)
			}
			out = args[i]
		case:
			fmt.eprintfln("unknown flag %s", args[i])
			os.exit(2)
		}
	}

	changed, identical, ok := render.diff_files(a_path, b_path, tile, out)
	if !ok {
		fmt.eprintfln("img-diff: could not read %s or %s", a_path, b_path)
		os.exit(1)
	}
	fmt.print(render.diff_summary(changed, identical))
	if !identical && out != "" {
		fmt.printfln("highlight written to %s", out)
	}
	if !identical {
		os.exit(1) // a plain non-zero exit doubles as a scriptable "did it change" check
	}
}
