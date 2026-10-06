# Streams

**`jm:stream` builds typed pipelines that never block, run on one thread or a
pool, and test deterministically.**

- **No thread per stage, no select.** A node runs only when one of its edges
  changed, drains what it can, and yields.
- **Back pressure for free.** Edges are bounded, so a fast producer waits for
  a slow consumer instead of filling memory.
- **Cheap hops.** On a 24-core desktop a message costs about 20 ns per stage.
- **Tests you can step through.** `step` runs one node at a time, and a manual
  `Clock` drives timers from the test.
- **Built for a frame loop.** `latest`, `debounce_by` and `pin` connect a
  pipeline to a UI without stalling either.

## Quick start

```odin
square :: proc(x: int) -> int {return x * x}
even :: proc(x: int) -> bool {return x % 2 == 0}

main :: proc() {
	p := stream.make_pipeline(context.allocator)
	defer stream.destroy(p)

	got: [dynamic]int
	nums := stream.from_slice(p, []int{1, 2, 3, 4, 5, 6})
	stream.collect(stream.filter(stream.transform(nums, square), even), &got)
	stream.run(p)

	fmt.println(got[:]) // [4, 16, 36]
}
```

Typed operators build a DAG of nodes joined by bounded edges, and a driver
runs the nodes.

## Where blocking goes

A node never blocks. Blocking lives at the edges of the pipeline:

- **A `port`** is fed by a thread of your own.
- **`workers`** run a blocking job and report back through an inlet.

## Drivers

| Call | What it does |
|------|--------------|
| `run(p)` | Drives the pipeline on the calling thread plus a pool sized from the graph, at most three threads. The measurements below say a pool of that size is never a loss. |
| `run(p, n)` | Asks for `n` threads. |
| `run(p, 0)` | Uses no extra threads. |
| `step` | Runs one node, for a deterministic test; the first call starts the sources. |

A `Clock` can be manual, so the test drives the timers.

## Fan-in: zip and merge

> [!WARNING]
> `zip` waits on a particular input. A source that reaches a zip along two
> paths of different rate would deadlock on it.

Building such a graph panics at the `zip` call. The panic names the shared
source and the stage that changes the count. Paths of one-in-one-out stages
are allowed, since they stay in step.

Merge never waits on one input, so it is safe to fan into.

## Connecting a pipeline to a frame loop

| Piece | What it solves |
|-------|----------------|
| `latest` | A sink another thread reads with `latest_take`. It keeps only the newest message and never parks its producer. |
| `debounce_by` | `debounce` per key: a burst of changes to one record settles to one message without holding up another record's. |
| `pin` | Keeps a node off the pool, for work that must run on one thread, such as a texture upload. |

With `latest`, a loop that stops reading never stalls the pipeline; its window
might be hidden, say. A burst of answers costs the next frame one take.

A pinned node never runs under `run`. The owning thread runs what is ready of
them with `drain_pinned`, once a frame, and `p.wake` is called when one
becomes ready so that thread can be told. `step` and `drain` run pinned nodes
too, since the one thread driving is the owner.

## Safety checks

In debug and test builds:

- every yield is checked against the edges when the run is single-threaded;
- a pool run fails loudly if the pipeline goes quiet with a node unfinished.

`-define:STREAM_CHECK_YIELDS=false` turns both off.

## Performance

Measured on a 24-core desktop.

| Measure | Result |
|---------|--------|
| Cost of a stage hop | about 20 ns |
| Work per message before a pool pays, chain or fan-out of a few branches | roughly 50 ns |
| Work per message before eight branches fill eight threads | roughly 200 ns |

Reproduce them on your own machine:

```
just stream-bench                              what a message costs through each shape
just stream-bench crossover                    where a pool starts to beat one thread
just stream-stress "-nodes=2000 -for=5m"       random DAGs of that size until time is up
```

`stream-bench crossover` burns a chosen amount of work per stage. The stress
run checks every sink's count against a model.

## Tested by fuzzing

`stream/fuzz` is the suite: fourteen properties over random graphs. It draws
the next node from the case's entropy to stand in for a pool's interleaving,
then runs again on real threads.

```
just fuzz "stream -for=1m"
```

## See also

- [Fuzzing](fuzzing.md): how the suite generates and shrinks cases
- [UI](ui.md): the todo and files apps join their threads with a pipeline
- [Packages](packages.md): `stream/ring`, the ring each edge is built on
