// sort: branchy integer work over an array that does not fit in L1.
static int a[1 << 14];

static void shell_sort(int *v, int n) {
	for (int gap = n / 2; gap > 0; gap /= 2)
		for (int i = gap; i < n; i++) {
			int t = v[i], j = i;
			for (; j >= gap && v[j - gap] > t; j -= gap) v[j] = v[j - gap];
			v[j] = t;
		}
}

__attribute__((export_name("run")))
int run(int n) {
	int acc = 0;
	for (int rep = 0; rep < n; rep++) {
		unsigned seed = 12345u + (unsigned)rep;
		for (int i = 0; i < (1 << 14); i++) {
			seed = seed * 1103515245u + 12345u;
			a[i] = (int)(seed >> 8);
		}
		shell_sort(a, 1 << 14);
		acc += a[0] ^ a[(1 << 14) - 1];
	}
	return acc;
}
