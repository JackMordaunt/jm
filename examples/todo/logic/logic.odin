/*
Package logic is the todo application's business processes: for each
command, given the facts the host gathered for it, the domains' decisions
and the one Effect they come to. It is pure. It reads nothing, writes
nothing and keeps nothing, so it is tested by calling effect.

The layers, and who runs them, per command, on the store's thread:

	enrich   the host reads the Facts the command needs      (app, store)
	decide   the domains judge                              (title, completion)
	effect   this package maps command, facts and verdicts to an Effect
	execute  the host carries the Effect out, one exhaustive switch (app)

What the same verdict means is decided here, never in the executor: an
empty title refuses an Add, and deletes on Edit, as TodoMVC does.
*/
package todo_logic

import "../completion"
import "../title"
import "../todo"

// Facts is what the host gathers about the world before a command is
// decided; each command reads only its own.
Facts :: struct {
	exists: bool, // Toggle, Edit: the todo is still there
	done:   bool, // Toggle: whether it is done
	active: int, // Toggle_All: how many todos are not done
}

// Effect is every change the application makes. A nil Effect is a
// command that changes nothing.
Effect :: union {
	Insert,
	Set_Done,
	Set_All,
	Set_Title,
	Remove,
	Remove_Done,
	Report,
	Withdraw,
}

Insert :: struct {
	title: todo.Text,
}

Set_Done :: struct {
	id:   i64,
	done: bool,
}

Set_All :: struct {
	done: bool,
}

Set_Title :: struct {
	id:    i64,
	title: todo.Text,
}

Remove :: struct {
	id: i64,
}

Remove_Done :: struct {}

// Report adds a problem to query.Problems.
Report :: struct {
	message: string,
}

// Withdraw removes a problem from query.Problems.
Withdraw :: struct {
	id: u64,
}

NO_TITLE :: "A todo needs a title."
TOO_LONG :: "That title is too long to keep."
GONE :: "That todo is no longer there."

// effect is what command c comes to, given the facts f.
effect :: proc(c: todo.Command, f: Facts) -> Effect {
	c := c
	switch &v in c {
	case todo.Add:
		validity, kept := title.validity(&v.title)
		switch validity {
		case .Empty:
			return Report{NO_TITLE}
		case .Too_Long:
			return Report{TOO_LONG}
		case .Valid:
			return Insert{todo.text_make(kept)}
		}
	case todo.Edit:
		if !f.exists {
			return Report{GONE}
		}
		validity, kept := title.validity(&v.title)
		switch validity {
		case .Empty:
			return Remove{v.id}
		case .Too_Long:
			return Report{TOO_LONG}
		case .Valid:
			return Set_Title{v.id, todo.text_make(kept)}
		}
	case todo.Toggle:
		if !f.exists {
			return Report{GONE}
		}
		return Set_Done{v.id, completion.toggled(f.done)}
	case todo.Toggle_All:
		return Set_All{completion.all_done(f.active)}
	case todo.Delete:
		// A todo already gone is as deleted as the user wanted.
		return Remove{v.id}
	case todo.Clear_Completed:
		return Remove_Done{}
	case todo.Dismiss:
		return Withdraw{v.id}
	}
	return nil
}
