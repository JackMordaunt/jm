/*
m3e-tokens parses the Jetpack Compose Material 3 token sources (the
generated *Tokens.kt files) into design-token JSON.

	m3e-tokens <source-dir> <out-dir>

<source-dir> holds the .kt files under tokens, and COMMIT, the androidx
commit they were fetched at. Two files are written to <out-dir>: m3e.tokens.json, a DTCG
2025.10 document with references intact, and m3e.resolved.json, every
token flat with its references followed to final values.

Any expression the parser does not recognise is an error: a changed
upstream should fail the build, not drop tokens quietly.
*/
package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

TOKENS_PATH :: "compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/tokens"

fail :: proc(format: string, args: ..any) -> ! {
	fmt.eprint("m3e-tokens: ")
	fmt.eprintfln(format, ..args)
	os.exit(1)
}

// load parses every *Tokens.kt in dir and checks the result is whole.
load :: proc(dir: string) -> ^Tokens {
	entries, err := os.read_all_directory_by_path(dir, context.allocator)
	if err != nil {
		fail("cannot read %s: %v", dir, err)
	}
	slice.sort_by(entries, proc(a, b: os.File_Info) -> bool { return a.name < b.name })
	t := new(Tokens)
	for e in entries {
		if !strings.has_suffix(e.name, "Tokens.kt") {
			continue
		}
		src, rerr := os.read_entire_file_from_path(e.fullpath, context.allocator)
		if rerr != nil {
			fail("cannot read %s: %v", e.fullpath, rerr)
		}
		add_file(t, string(src), e.name)
	}
	check(t)
	return t
}

main :: proc() {
	if len(os.args) != 3 {
		fail("usage: m3e-tokens <source-dir> <out-dir>")
	}
	srcDir, outDir := os.args[1], os.args[2]
	commit, cerr := os.read_entire_file_from_path(fmt.tprintf("%s/COMMIT", srcDir), context.allocator)
	if cerr != nil {
		fail("cannot read %s/COMMIT: %v", srcDir, cerr)
	}
	src := Source{"androidx/androidx", strings.trim_space(string(commit)), TOKENS_PATH}

	t := load(fmt.tprintf("%s/tokens", srcDir))
	dtcg := write_dtcg(t, src)
	resolved := write_resolved(t, src)
	if len(t.errors) > 0 {
		for e in t.errors {
			fmt.eprintln(e)
		}
		fail("%d errors; nothing written", len(t.errors))
	}
	for f in ([][2]string{{"m3e.tokens.json", dtcg}, {"m3e.resolved.json", resolved}}) {
		path := fmt.tprintf("%s/%s", outDir, f[0])
		if werr := os.write_entire_file(path, f[1]); werr != nil {
			fail("cannot write %s: %v", path, werr)
		}
	}
	fmt.printfln("m3e-tokens: %d tokens from %s", len(t.order), src.commit[:12])
}
