// mandel: f64 arithmetic in a tight loop, no memory to speak of.
__attribute__((export_name("run")))
int run(int n) {
	int acc = 0;
	for (int rep = 0; rep < n; rep++) {
		for (int py = 0; py < 24; py++) {
			double y0 = (double)py / 12.0 - 1.0;
			for (int px = 0; px < 32; px++) {
				double x0 = (double)px / 16.0 - 2.0;
				double x = 0, y = 0;
				int it = 0;
				while (x * x + y * y <= 4.0 && it < 200) {
					double t = x * x - y * y + x0;
					y = 2.0 * x * y + y0;
					x = t;
					it++;
				}
				acc += it;
			}
		}
	}
	return acc;
}
