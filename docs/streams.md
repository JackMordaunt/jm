# Streams

`stream` is a dataflow pipeline: typed operators build a DAG of nodes joined
by bounded edges, and a driver runs the nodes. A node runs only when an edge
changed and never blocks, so there is no thread per stage and no select;
blocking lives at the edges, in a thread feeding a `port` or in `workers`
doing a job and reporting through an inlet. `run(p)` drives a pipeline on
the calling thread plus a pool sized from the graph, at most three threads,
which is where the measurements below say a pool is never a loss; `run(p, n)`
asks for `n` threads, `run(p, 0)` for none; `step` runs one node for a
deterministic test, and a `Clock` can be manual so timers are driven by the
test.

Bounded edges carry one caveat: `zip` waits on a particular input, so a source
that reaches a zip along two paths of different rate would deadlock on it.
Building such a graph panics at the `zip` call, naming the shared source and
the stage that changes the count; paths of one-in-one-out stages are allowed,
since they stay in step. Merge never waits on one input and is safe to fan
into.

Three pieces serve a frame loop. `latest` is a sink another thread reads
with `latest_take`: it keeps only the newest message and never parks its
producer, so a loop that stops reading, with its window hidden say, never
stalls the pipeline, and a burst of answers costs the next frame one take.
`debounce_by` is `debounce` per key: a burst of changes to one record
settles to one message without holding up another record's. `pin` keeps a
node off the pool, for work that must run on one thread, a texture upload
say: `run` never runs it, the owning thread runs what is ready of them with
`drain_pinned`, once a frame, and `p.wake` is called when one becomes ready
so that thread can be told. `step` and `drain` run pinned nodes too, since
the one thread driving is the owner.

In debug and test builds every yield is checked against the edges when the
run is single-threaded, and a pool run fails loudly if the pipeline goes
quiet with a node unfinished. `-define:STREAM_CHECK_YIELDS=false` turns both
off.

`stream/fuzz` is the suite: fourteen properties over random graphs, with the
next node drawn from the case's entropy to stand in for a pool's interleaving,
and again on real threads. `just fuzz "stream -for=1m"` runs it.
`just stream-bench` prints what a message costs through each shape,
`just stream-bench crossover` burns a chosen amount of work per stage and
shows where a pool starts to beat one thread, and
`just stream-stress "-nodes=2000 -for=5m"` runs random DAGs of that size
until the time is up, checking every sink's count against a model. On a
24-core desktop a stage hop costs about 20 ns, and a pool pays once a stage
does roughly 50 ns of work per message for a chain or fan-out of a few
branches, and 200 ns before eight branches fill eight threads.
