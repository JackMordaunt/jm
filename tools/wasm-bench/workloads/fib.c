// fib: recursive calls over i32, to stress call and return rather than
// arithmetic or memory.
static int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }

// The argument to fib changes with the loop counter, because a compiler that
// can see fib is pure hoists a constant call straight out of the loop and the
// benchmark then measures one call however large n is.
__attribute__((export_name("run")))
int run(int n) {
	int acc = 0;
	for (int i = 0; i < n; i++) acc = acc * 31 + fib(20 + (i & 1));
	return acc;
}
