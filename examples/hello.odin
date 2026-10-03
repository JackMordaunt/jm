#!/usr/bin/env odin-run
// A script that touches every package. Run it as ./hello.odin once odin-run
// is installed, or with `just odin-run-example`.
package main

import "core:fmt"
import "core:log"
import "core:time"

import "jm:http"
import "jm:path"
import "jm:prelude"
import "jm:sh"
import "jm:sqlite3"
import "jm:timefmt"

must :: prelude.must
die  :: prelude.die

main :: proc() {
	context = prelude.init()
	log.infof("started at %s", timefmt.local(time.now(), "%H:%M:%S %Z", context.temp_allocator))

	// Shell: a string through the platform shell, or argv without quoting.
	shell := "cmd" when ODIN_OS == .Windows else "sh"
	shell_path := must(sh.which(shell))
	fmt.println("shell:", shell_path)
	fmt.println("echo:", must(sh.out("echo hello from the shell")))
	r := sh.exec({shell_path, "-c" if ODIN_OS != .Windows else "/C", "exit 2"})
	if !r.ok {
		log.warnf("expected failure: %s", sh.error(r, context.temp_allocator))
	}

	// Files: a scratch tree, written and read back.
	scratch := must(path.temp_dir("hello-"))
	defer path.remove_all(scratch)
	note := path.join(scratch, "notes", "today.txt")
	must(
		path.write(
			note,
			fmt.tprintf("written %s\n", timefmt.iso(time.now(), context.temp_allocator)),
		),
	)
	for line in must(path.read_lines(note)) {
		fmt.println("note:", line)
	}
	fmt.println("files:", len(must(path.walk(scratch))))

	// SQLite: a database in the scratch tree, written and read back.
	db := must(sqlite3.open(path.join(scratch, "hello.db")))
	defer sqlite3.close(&db)
	must(sqlite3.exec(db, `CREATE TABLE note(at TEXT, body TEXT)`))
	must(
		sqlite3.exec_args(
			db,
			`INSERT INTO note VALUES (?, ?)`,
			timefmt.iso(time.now(), context.temp_allocator),
			"it isn't interpolated",
		),
	)
	rows := must(sqlite3.query(db, `SELECT at, body FROM note`))
	defer sqlite3.finish(&rows)
	for sqlite3.next(&rows) {
		fmt.println("note:", sqlite3.text(rows, 0), sqlite3.text(rows, 1))
	}
	fmt.println("sqlite:", sqlite3.version())

	// HTTP: skipped without HELLO_URL so the example runs offline.
	if url := prelude.env("HELLO_URL"); url != "" {
		res := must(http.get(url, {timeout = 10 * time.Second}))
		fmt.printf("GET %s -> %d, %d bytes\n", url, res.status, len(res.body))
	}

	if len(prelude.args()) > 0 && prelude.args()[0] == "die" {
		die("asked to die")
	}
	fmt.println("log:", prelude.log_path())
}
