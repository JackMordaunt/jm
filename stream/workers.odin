package stream

import "core:container/queue"
import "core:mem"
import "core:sync"
import "core:thread"

/*
Workers run blocking work off the driver. A job is a proc and a pointer; it
reports back by pushing into an inlet, which is how a completion reaches the
node that asked for it. Stop the workers before destroying a pipeline whose
nodes they report to.
*/
Workers :: struct {
	allocator: mem.Allocator,
	threads:   []^thread.Thread,
	mutex:     sync.Mutex,
	more:      sync.Cond,
	jobs:      queue.Queue(Job),
	stopping:  bool,
}

Job :: struct {
	run:  proc(data: rawptr),
	data: rawptr,
}

// Start `count` threads. They inherit the calling context.
workers_start :: proc(count: int, allocator: mem.Allocator) -> ^Workers {
	w := new(Workers, allocator)
	w.allocator = allocator
	queue.init(&w.jobs, 16, allocator)
	w.threads = make([]^thread.Thread, count, allocator)
	for &t in w.threads {
		t = thread.create_and_start_with_data(w, worker_main, context)
	}
	return w
}

// Finish the queued jobs, then join every thread and free the pool.
workers_stop :: proc(w: ^Workers) {
	sync.mutex_lock(&w.mutex)
	w.stopping = true
	sync.mutex_unlock(&w.mutex)
	sync.cond_broadcast(&w.more)
	for t in w.threads {
		thread.join(t)
		thread.destroy(t)
	}
	delete(w.threads, w.allocator)
	queue.destroy(&w.jobs)
	free(w, w.allocator)
}

submit :: proc(w: ^Workers, run: proc(data: rawptr), data: rawptr) {
	sync.mutex_lock(&w.mutex)
	queue.push_back(&w.jobs, Job{run, data})
	sync.mutex_unlock(&w.mutex)
	sync.cond_signal(&w.more)
}

@(private)
worker_main :: proc(data: rawptr) {
	w := (^Workers)(data)
	for {
		sync.mutex_lock(&w.mutex)
		for queue.len(w.jobs) == 0 && !w.stopping {
			sync.cond_wait(&w.more, &w.mutex)
		}
		if queue.len(w.jobs) == 0 {
			sync.mutex_unlock(&w.mutex)
			return
		}
		job := queue.pop_front(&w.jobs)
		sync.mutex_unlock(&w.mutex)
		job.run(job.data)
	}
}
