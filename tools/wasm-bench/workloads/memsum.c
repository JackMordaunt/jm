// memsum: linear memory traffic. A megabyte written and read back per unit,
// to stress a runtime's memory access rather than its arithmetic.
static unsigned char buf[1 << 20];

__attribute__((export_name("run")))
int run(int n) {
	unsigned acc = 0;
	for (int rep = 0; rep < n; rep++) {
		for (int i = 0; i < (1 << 20); i += 4) buf[i] = (unsigned char)(i + rep);
		for (int i = 0; i < (1 << 20); i += 4) acc += buf[i];
	}
	return (int)acc;
}
