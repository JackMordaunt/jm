/*
Package testdb brings up a throwaway PostgreSQL server for jm:pq's tests and
its fuzz suite, and points libpq's environment at it.

	if ok, why := testdb.start(); !ok {
		log.warnf("no server, skipping: %s", why)
		return
	}
	conn, err := pq.connect() // PGHOST and friends now name the throwaway

start runs `initdb` into a fresh directory under the system temp location and
`pg_ctl start` on it, listening on a Unix socket in that directory and on no
TCP address at all, so nothing outside this machine's file system can reach
it and it cannot collide with a server already on port 5432. Authentication is
`trust`: the socket's directory is the only door, and it is private to the
user running the tests.

It then clears every PG* variable from the environment and sets PGHOST,
PGPORT, PGUSER and PGDATABASE to the throwaway. Clearing comes first because
a developer's shell often exports PGHOSTADDR, PGSERVICE or PGPASSWORD for a
real database, and any one of them would send a test somewhere else.

The server comes up once per process, however many tests or threads ask for
it. A child process that inherits the environment — jm:fuzz's -isolate runs
each case in one — finds JM_PQ_TESTDB set and uses the running server rather
than starting another.

Teardown does not depend on the process ending cleanly. start leaves a small
shell loop behind that waits for this process to be gone, however it went —
a return from main, os.exit, a failed assertion, a sanitizer abort, a kill —
and then stops the server and deletes the directory. An @(fini) procedure
would miss os.exit, which core:os documents as skipping @(fini), and every
way of dying that is not a return.

If initdb or pg_ctl is not on PATH, start reports why and returns false, and
the caller skips. Nothing here needs a server to exist beforehand. Unix only:
on Windows start always returns false.
*/
package testdb

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"

import "jm:path"
import "jm:sh"

// ENV names the variable that marks a server this process, or its parent,
// already started. Its value is the directory the server lives in.
ENV :: "JM_PQ_TESTDB"

// USER and DATABASE are what the throwaway is initialised with. The
// superuser is named explicitly so the tests do not depend on the name of
// whoever runs them.
USER :: "postgres"
DATABASE :: "postgres"

// PORT only names the socket file, .s.PGSQL.5432; nothing listens on TCP.
PORT :: "5432"

@(private)
state: struct {
	mutex:   sync.Mutex,
	tried:   bool,
	ok:      bool,
	why:     string,
	dir:     string,
}

// start makes sure a throwaway server is running and that the PG* variables
// name it, and reports why not when it cannot. It is safe to call from every
// test; only the first call does any work.
start :: proc() -> (ok: bool, why: string) {
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)
	if !state.tried {
		state.tried = true
		// What start keeps outlives whichever test called it first, so it
		// comes from the heap rather than that test's allocator.
		context.allocator = runtime.heap_allocator()
		state.ok, state.why = bring_up()
	}
	return state.ok, state.why
}

// dir is the directory the server's socket is in, which is also PGHOST, or ""
// when no server is up.
dir :: proc() -> string {
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)
	return state.ok ? state.dir : ""
}

@(private)
bring_up :: proc() -> (ok: bool, why: string) {
	when ODIN_OS == .Windows {
		return false, "the throwaway server is only brought up on Unix"
	}
	if inherited, found := os.lookup_env(ENV, context.allocator); found && inherited != "" {
		if !os.exists(path.join(inherited, ".s.PGSQL." + PORT, allocator = context.temp_allocator)) {
			return false, fmt.aprintf("%s names %s, which has no server socket", ENV, inherited)
		}
		state.dir = inherited
		return true, ""
	}

	for tool in ([]string{"initdb", "pg_ctl"}) {
		if _, found := sh.which(tool, context.temp_allocator); !found {
			return false, fmt.aprintf("%s is not on PATH; install the PostgreSQL server package", tool)
		}
	}

	root, terr := path.temp_dir("jm-pq-")
	if terr != nil {
		return false, fmt.aprintf("cannot make a temp directory: %v", terr)
	}
	data := path.join(root, "data", allocator = context.temp_allocator)
	log := path.join(root, "server.log", allocator = context.temp_allocator)

	// --no-sync and fsync=off: the data is thrown away, so durability buys
	// nothing and costs seconds. UTF8 and the C locale make the server the
	// same on every machine whatever the caller's locale is.
	r := sh.exec(
		{"initdb", "-D", data, "-A", "trust", "-U", USER, "-E", "UTF8", "--no-locale", "--no-sync"},
		allocator = context.temp_allocator,
	)
	if !r.ok {
		_ = os.remove_all(root)
		return false, fmt.aprintf("initdb failed: %s", sh.error(r, context.temp_allocator))
	}

	options := fmt.tprintf("-k %s -p %s -c listen_addresses='' -c fsync=off", root, PORT)
	r = sh.exec(
		{"pg_ctl", "-D", data, "-l", log, "-o", options, "-w", "-s", "start"},
		allocator = context.temp_allocator,
	)
	if !r.ok {
		server_log, _ := path.read(log, context.temp_allocator)
		_ = os.remove_all(root)
		return false, fmt.aprintf(
			"pg_ctl start failed: %s\n%s",
			sh.error(r, context.temp_allocator),
			server_log,
		)
	}

	// The reaper. Its output goes nowhere, so a caller capturing this
	// process's stdout sees end of file when this process ends rather than
	// when the reaper does.
	reaper := fmt.tprintf(
		"(while kill -0 %d 2>/dev/null; do sleep 0.2; done; " +
		"pg_ctl -D %s -m immediate -s stop; rm -rf %s) </dev/null >/dev/null 2>&1 &",
		os.get_pid(),
		sh.quote(data, context.temp_allocator),
		sh.quote(root, context.temp_allocator),
	)
	if !sh.ok(reaper) {
		_ = sh.exec({"pg_ctl", "-D", data, "-m", "immediate", "-s", "stop"}, allocator = context.temp_allocator)
		_ = os.remove_all(root)
		return false, "cannot leave a reaper behind to stop the server"
	}

	point_at(root)
	state.dir = root
	return true, ""
}

// point_at clears every PG* variable and sets the four that name the
// throwaway, plus the marker a child process looks for.
@(private)
point_at :: proc(root: string) {
	env, _ := os.environ(context.temp_allocator)
	for kv in env {
		if strings.has_prefix(kv, "PG") {
			eq := strings.index_byte(kv, '=')
			if eq > 0 {
				os.unset_env(kv[:eq])
			}
		}
	}
	os.set_env("PGHOST", root)
	os.set_env("PGPORT", PORT)
	os.set_env("PGUSER", USER)
	os.set_env("PGDATABASE", DATABASE)
	os.set_env(ENV, root)
}
