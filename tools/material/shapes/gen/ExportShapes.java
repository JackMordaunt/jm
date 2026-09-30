// Exports Material 3 Expressive MaterialShapes (35 RoundedPolygons) and the
// LoadingIndicator morph pairs as plain cubic geometry.
//
// A line-for-line Java port of MaterialShapes.kt at androidx commit
// 1358a48e9c23e257ae3357f6f645cb60a3610a7f, run against the real
// androidx.graphics:graphics-shapes-desktop:1.0.1 (the version material3 pins).
// Compose Matrix/Offset are shimmed with float math that mirrors
// androidx.compose.ui.graphics.Matrix (rotateZ, scale, map).
//
// Usage: java -cp <jars> ExportShapes.java <out-dir>   (see README.md)

import androidx.graphics.shapes.CornerRounding;
import androidx.graphics.shapes.Cubic;
import androidx.graphics.shapes.Morph;
import androidx.graphics.shapes.PointTransformer;
import androidx.graphics.shapes.RoundedPolygon;
import androidx.graphics.shapes.RoundedPolygonKt;
import androidx.graphics.shapes.ShapesKt;

import java.io.IOException;
import java.lang.reflect.Proxy;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public class ExportShapes {
    static final String COMMIT = "1358a48e9c23e257ae3357f6f645cb60a3610a7f";
    static final float PI_F = (float) Math.PI;

    // ---- Compose shims -------------------------------------------------------

    /** 2D subset of androidx.compose.ui.graphics.Matrix (column-major m[col,row]). */
    static final class Mat {
        float m00 = 1, m01 = 0, m10 = 0, m11 = 1; // m[0,0], m[0,1], m[1,0], m[1,1]

        Mat rotateZ(float degrees) {
            double r = degrees * (Math.PI / 180.0);
            float s = (float) Math.sin(r), c = (float) Math.cos(r);
            float v00 = c * m00 + s * m10, v10 = -s * m00 + c * m10;
            float v01 = c * m01 + s * m11, v11 = -s * m01 + c * m11;
            m00 = v00; m10 = v10; m01 = v01; m11 = v11;
            return this;
        }

        Mat scale(float x, float y) {
            m00 *= x; m01 *= x; m10 *= y; m11 *= y;
            return this;
        }

        float[] map(float x, float y) {
            return new float[] {m00 * x + m10 * y, m01 * x + m11 * y};
        }
    }

    /** graphics-shapes TransformResult packs (x, y) float bits into one Long. */
    static long pack(float x, float y) {
        return ((long) Float.floatToRawIntBits(x) << 32) | (Float.floatToRawIntBits(y) & 0xFFFFFFFFL);
    }

    /** material3 internal RoundedPolygon.transformed(Matrix). PointTransformer's
     *  method name is mangled (value-class return), so implement it via Proxy. */
    static RoundedPolygon transformed(RoundedPolygon p, Mat m) {
        PointTransformer t = (PointTransformer) Proxy.newProxyInstance(
                ExportShapes.class.getClassLoader(),
                new Class<?>[] {PointTransformer.class},
                (proxy, method, args) -> {
                    if (method.getName().startsWith("transform")) {
                        float[] o = m.map((Float) args[0], (Float) args[1]);
                        return pack(o[0], o[1]);
                    }
                    if (method.getName().equals("hashCode")) return System.identityHashCode(proxy);
                    if (method.getName().equals("equals")) return proxy == args[0];
                    return "PointTransformer";
                });
        return p.transformed(t);
    }

    record Offset(float x, float y) {
        Offset minus(Offset o) { return new Offset(x - o.x, y - o.y); }
        Offset plus(Offset o) { return new Offset(x + o.x, y + o.y); }
        Offset times(float f) { return new Offset(x * f, y * f); }
        float getDistance() { return (float) Math.sqrt(x * x + y * y); }
        float angleDegrees() { return (float) Math.atan2(y, x) * 180f / PI_F; }
    }

    static float cos(float a) { return (float) Math.cos(a); }
    static float sin(float a) { return (float) Math.sin(a); }
    static float toRadians(float d) { return d / 360f * 2 * PI_F; }

    // ---- MaterialShapes port -------------------------------------------------

    static final CornerRounding UNROUNDED = CornerRounding.Unrounded;
    static CornerRounding cr(float r) { return new CornerRounding(r, 0f); }
    static CornerRounding cr(float r, float s) { return new CornerRounding(r, s); }

    static final CornerRounding cornerRound15 = cr(.15f);
    static final CornerRounding cornerRound20 = cr(.2f);
    static final CornerRounding cornerRound30 = cr(.3f);
    static final CornerRounding cornerRound50 = cr(.5f);
    static final CornerRounding cornerRound100 = cr(1f);

    static final Mat rotateNeg45 = new Mat().rotateZ(-45f);
    static final Mat rotateNeg90 = new Mat().rotateZ(-90f);
    static final Mat rotateNeg135 = new Mat().rotateZ(-135f);

    static final RoundedPolygon.Companion RP = RoundedPolygon.Companion;

    record PNR(Offset o, CornerRounding r) {}
    static PNR p(float x, float y) { return new PNR(new Offset(x, y), UNROUNDED); }
    static PNR p(float x, float y, CornerRounding r) { return new PNR(new Offset(x, y), r); }

    static RoundedPolygon circle(int numVertices) { return ShapesKt.circle(RP, numVertices); }
    static RoundedPolygon star(int n, float innerRadius, CornerRounding rounding) {
        return ShapesKt.star(RP, n, 1f, innerRadius, rounding);
    }
    static RoundedPolygon rectangle(float w, float h, CornerRounding rounding, List<CornerRounding> per) {
        return ShapesKt.rectangle(RP, w, h, rounding, per, 0f, 0f);
    }
    static RoundedPolygon polygon(int n, CornerRounding rounding, List<CornerRounding> per) {
        return RoundedPolygonKt.RoundedPolygon(n, 1f, 0f, 0f, rounding, per);
    }

    static RoundedPolygon circle() { return circle(10); }
    static RoundedPolygon square() { return rectangle(1f, 1f, cornerRound30, null); }
    static RoundedPolygon slanted() {
        return customPolygon(List.of(
                p(0.926f, 0.970f, cr(0.189f, 0.811f)),
                p(-0.021f, 0.967f, cr(0.187f, 0.057f))), 2);
    }
    static RoundedPolygon arch() {
        return transformed(polygon(4, UNROUNDED,
                List.of(cornerRound100, cornerRound100, cornerRound20, cornerRound20)), rotateNeg135);
    }
    static RoundedPolygon fan() {
        return customPolygon(List.of(
                p(1.004f, 1.000f, cr(0.148f, 0.417f)),
                p(0.000f, 1.000f, cr(0.151f)),
                p(0.000f, -0.003f, cr(0.148f)),
                p(0.978f, 0.020f, cr(0.803f))), 1);
    }
    static RoundedPolygon arrow() {
        return customPolygon(List.of(
                p(0.500f, 0.892f, cr(0.313f)),
                p(-0.216f, 1.050f, cr(0.207f)),
                p(0.499f, -0.160f, cr(0.215f, 1.000f)),
                p(1.225f, 1.060f, cr(0.211f))), 1);
    }
    static RoundedPolygon semiCircle() {
        return rectangle(1.6f, 1f, UNROUNDED,
                List.of(cornerRound20, cornerRound20, cornerRound100, cornerRound100));
    }
    static RoundedPolygon oval() {
        Mat m = new Mat().scale(1f, 0.64f);
        return transformed(transformed(ShapesKt.circle(RP), m), rotateNeg45);
    }
    static RoundedPolygon pill() {
        return customPolygon(List.of(
                p(0.961f, 0.039f, cr(0.426f)),
                p(1.001f, 0.428f),
                p(1.000f, 0.609f, cr(1.000f))), 2, true);
    }
    static RoundedPolygon triangle() {
        return transformed(polygon(3, cornerRound20, null), rotateNeg90);
    }
    static RoundedPolygon diamond() {
        return customPolygon(List.of(
                p(0.500f, 1.096f, cr(0.151f, 0.524f)),
                p(0.040f, 0.500f, cr(0.159f))), 2);
    }
    static RoundedPolygon clamShell() {
        return customPolygon(List.of(
                p(0.171f, 0.841f, cr(0.159f)),
                p(-0.020f, 0.500f, cr(0.140f)),
                p(0.170f, 0.159f, cr(0.159f))), 2);
    }
    static RoundedPolygon pentagon() {
        return customPolygon(List.of(
                p(0.500f, -0.009f, cr(0.172f)),
                p(1.030f, 0.365f, cr(0.164f)),
                p(0.828f, 0.970f, cr(0.169f))), 1, true);
    }
    static RoundedPolygon gem() {
        return customPolygon(List.of(
                p(0.499f, 1.023f, cr(0.241f, 0.778f)),
                p(-0.005f, 0.792f, cr(0.208f)),
                p(0.073f, 0.258f, cr(0.228f)),
                p(0.433f, -0.000f, cr(0.491f))), 1, true);
    }
    static RoundedPolygon sunny() { return star(8, .8f, cornerRound15); }
    static RoundedPolygon verySunny() {
        return customPolygon(List.of(
                p(0.500f, 1.080f, cr(0.085f)),
                p(0.358f, 0.843f, cr(0.085f))), 8);
    }
    static RoundedPolygon cookie4() {
        return customPolygon(List.of(
                p(1.237f, 1.236f, cr(0.258f)),
                p(0.500f, 0.918f, cr(0.233f))), 4);
    }
    static RoundedPolygon cookie6() {
        return customPolygon(List.of(
                p(0.723f, 0.884f, cr(0.394f)),
                p(0.500f, 1.099f, cr(0.398f))), 6);
    }
    static RoundedPolygon cookie7() { return transformed(star(7, .75f, cornerRound50), rotateNeg90); }
    static RoundedPolygon cookie9() { return transformed(star(9, .8f, cornerRound50), rotateNeg90); }
    static RoundedPolygon cookie12() { return transformed(star(12, .8f, cornerRound50), rotateNeg90); }
    static RoundedPolygon ghostish() {
        return customPolygon(List.of(
                p(0.500f, 0f, cr(1.000f)),
                p(1f, 0f, cr(1.000f)),
                p(1f, 1.140f, cr(0.254f, 0.106f)),
                p(0.575f, 0.906f, cr(0.253f))), 1, true);
    }
    static RoundedPolygon clover4() {
        return customPolygon(List.of(
                p(0.500f, 0.074f),
                p(0.725f, -0.099f, cr(0.476f))), 4, true);
    }
    static RoundedPolygon clover8() {
        return customPolygon(List.of(
                p(0.500f, 0.036f),
                p(0.758f, -0.101f, cr(0.209f))), 8);
    }
    static RoundedPolygon burst() {
        return customPolygon(List.of(
                p(0.500f, -0.006f, cr(0.006f)),
                p(0.592f, 0.158f, cr(0.006f))), 12);
    }
    static RoundedPolygon softBurst() {
        return customPolygon(List.of(
                p(0.193f, 0.277f, cr(0.053f)),
                p(0.176f, 0.055f, cr(0.053f))), 10);
    }
    static RoundedPolygon boom() {
        return customPolygon(List.of(
                p(0.457f, 0.296f, cr(0.007f)),
                p(0.500f, -0.051f, cr(0.007f))), 15);
    }
    static RoundedPolygon softBoom() {
        return customPolygon(List.of(
                p(0.733f, 0.454f),
                p(0.839f, 0.437f, cr(0.532f)),
                p(0.949f, 0.449f, cr(0.439f, 1.000f)),
                p(0.998f, 0.478f, cr(0.174f))), 16, true);
    }
    static RoundedPolygon flower() {
        return customPolygon(List.of(
                p(0.370f, 0.187f),
                p(0.416f, 0.049f, cr(0.381f)),
                p(0.479f, 0.001f, cr(0.095f))), 8, true);
    }
    static RoundedPolygon puffy() {
        Mat m = new Mat().scale(1f, 0.742f);
        return transformed(customPolygon(List.of(
                p(0.500f, 0.053f),
                p(0.545f, -0.040f, cr(0.405f)),
                p(0.670f, -0.035f, cr(0.426f)),
                p(0.717f, 0.066f, cr(0.574f)),
                p(0.722f, 0.128f),
                p(0.777f, 0.002f, cr(0.360f)),
                p(0.914f, 0.149f, cr(0.660f)),
                p(0.926f, 0.289f, cr(0.660f)),
                p(0.881f, 0.346f),
                p(0.940f, 0.344f, cr(0.126f)),
                p(1.003f, 0.437f, cr(0.255f))), 2, true), m);
    }
    static RoundedPolygon puffyDiamond() {
        return customPolygon(List.of(
                p(0.870f, 0.130f, cr(0.146f)),
                p(0.818f, 0.357f),
                p(1.000f, 0.332f, cr(0.853f))), 4, true);
    }
    static RoundedPolygon pixelCircle() {
        return customPolygon(List.of(
                p(0.500f, 0.000f),
                p(0.704f, 0.000f),
                p(0.704f, 0.065f),
                p(0.843f, 0.065f),
                p(0.843f, 0.148f),
                p(0.926f, 0.148f),
                p(0.926f, 0.296f),
                p(1.000f, 0.296f)), 2, true);
    }
    static RoundedPolygon pixelTriangle() {
        return customPolygon(List.of(
                p(0.110f, 0.500f),
                p(0.113f, 0.000f),
                p(0.287f, 0.000f),
                p(0.287f, 0.087f),
                p(0.421f, 0.087f),
                p(0.421f, 0.170f),
                p(0.560f, 0.170f),
                p(0.560f, 0.265f),
                p(0.674f, 0.265f),
                p(0.675f, 0.344f),
                p(0.789f, 0.344f),
                p(0.789f, 0.439f),
                p(0.888f, 0.439f)), 1, true);
    }
    static RoundedPolygon bun() {
        return customPolygon(List.of(
                p(0.796f, 0.500f),
                p(0.853f, 0.518f, cr(1f)),
                p(0.992f, 0.631f, cr(1f)),
                p(0.968f, 1.000f, cr(1f))), 2, true);
    }
    static RoundedPolygon heart() {
        return customPolygon(List.of(
                p(0.500f, 0.268f, cr(0.016f)),
                p(0.792f, -0.066f, cr(0.958f)),
                p(1.064f, 0.276f, cr(1.000f)),
                p(0.501f, 0.946f, cr(0.129f))), 1, true);
    }

    static List<PNR> doRepeat(List<PNR> points, int reps, Offset center, boolean mirroring) {
        List<PNR> out = new ArrayList<>();
        if (mirroring) {
            int n = points.size();
            float[] angles = new float[n], distances = new float[n];
            for (int k = 0; k < n; k++) {
                angles[k] = points.get(k).o.minus(center).angleDegrees();
                distances[k] = points.get(k).o.minus(center).getDistance();
            }
            int actualReps = reps * 2;
            float sectionAngle = 360f / actualReps;
            for (int it = 0; it < actualReps; it++) {
                for (int index = 0; index < n; index++) {
                    int i = (it % 2 == 0) ? index : (n - 1) - index;
                    if (i > 0 || it % 2 == 0) {
                        float a = toRadians(sectionAngle * it
                                + ((it % 2 == 0) ? angles[i] : sectionAngle - angles[i] + 2 * angles[0]));
                        Offset fin = new Offset(cos(a), sin(a)).times(distances[i]).plus(center);
                        out.add(new PNR(fin, points.get(i).r));
                    }
                }
            }
        } else {
            int np = points.size();
            for (int it = 0; it < np * reps; it++) {
                Offset pt = rotateDegrees(points.get(it % np).o, (it / np) * 360f / reps, center);
                out.add(new PNR(pt, points.get(it % np).r));
            }
        }
        return out;
    }

    static Offset rotateDegrees(Offset o, float angle, Offset center) {
        float a = toRadians(angle);
        Offset off = o.minus(center);
        return new Offset(off.x * cos(a) - off.y * sin(a), off.x * sin(a) + off.y * cos(a)).plus(center);
    }

    static RoundedPolygon customPolygon(List<PNR> pnr, int reps) { return customPolygon(pnr, reps, false); }

    static RoundedPolygon customPolygon(List<PNR> pnr, int reps, boolean mirroring) {
        Offset center = new Offset(0.5f, 0.5f);
        List<PNR> pts = doRepeat(pnr, reps, center, mirroring);
        float[] v = new float[pts.size() * 2];
        List<CornerRounding> per = new ArrayList<>();
        for (int i = 0; i < pts.size(); i++) {
            v[2 * i] = pts.get(i).o.x;
            v[2 * i + 1] = pts.get(i).o.y;
            per.add(pts.get(i).r);
        }
        return RoundedPolygonKt.RoundedPolygon(v, UNROUNDED, per, center.x, center.y);
    }

    /** Public MaterialShapes properties, in declaration order: name -> normalized polygon. */
    static Map<String, RoundedPolygon> materialShapes() {
        Map<String, RoundedPolygon> s = new LinkedHashMap<>();
        s.put("circle", circle().normalized());
        s.put("square", square().normalized());
        s.put("slanted", slanted().normalized());
        s.put("arch", arch().normalized());
        s.put("fan", fan().normalized());
        s.put("arrow", arrow().normalized());
        s.put("semi-circle", semiCircle().normalized());
        s.put("oval", oval().normalized());
        s.put("pill", pill().normalized());
        s.put("triangle", triangle().normalized());
        s.put("diamond", diamond().normalized());
        s.put("clam-shell", clamShell().normalized());
        s.put("pentagon", pentagon().normalized());
        s.put("gem", gem().normalized());
        s.put("sunny", sunny().normalized());
        s.put("very-sunny", verySunny().normalized());
        s.put("cookie-4-sided", cookie4().normalized());
        s.put("cookie-6-sided", cookie6().normalized());
        s.put("cookie-7-sided", cookie7().normalized());
        s.put("cookie-9-sided", cookie9().normalized());
        s.put("cookie-12-sided", cookie12().normalized());
        s.put("ghostish", ghostish().normalized());
        s.put("clover-4-leaf", clover4().normalized());
        s.put("clover-8-leaf", clover8().normalized());
        s.put("burst", burst().normalized());
        s.put("soft-burst", softBurst().normalized());
        s.put("boom", boom().normalized());
        s.put("soft-boom", softBoom().normalized());
        s.put("flower", flower().normalized());
        s.put("puffy", puffy().normalized());
        s.put("puffy-diamond", puffyDiamond().normalized());
        s.put("pixel-circle", pixelCircle().normalized());
        s.put("pixel-triangle", pixelTriangle().normalized());
        s.put("bun", bun().normalized());
        s.put("heart", heart().normalized());
        return s;
    }

    // ---- Output --------------------------------------------------------------

    static String num(double v, int decimals) {
        String s = String.format(Locale.ROOT, "%." + decimals + "f", v);
        if (s.contains(".")) s = s.replaceAll("0+$", "").replaceAll("\\.$", "");
        if (s.equals("-0")) s = "0";
        return s;
    }

    static float[] pts(Cubic c) {
        return new float[] {c.getAnchor0X(), c.getAnchor0Y(), c.getControl0X(), c.getControl0Y(),
                c.getControl1X(), c.getControl1Y(), c.getAnchor1X(), c.getAnchor1Y()};
    }

    static String cubicsJson(List<Cubic> cubics, String indent) {
        StringBuilder b = new StringBuilder("[\n");
        for (int i = 0; i < cubics.size(); i++) {
            float[] p = pts(cubics.get(i));
            b.append(indent).append("  [");
            for (int k = 0; k < 8; k++) b.append(k == 0 ? "" : ",").append(num(p[k], 5));
            b.append(i + 1 < cubics.size() ? "],\n" : "]\n");
        }
        return b.append(indent).append("]").toString();
    }

    static String svg(List<Cubic> cubics) {
        StringBuilder d = new StringBuilder();
        for (int i = 0; i < cubics.size(); i++) {
            float[] p = pts(cubics.get(i));
            if (i == 0) d.append("M").append(num(p[0] * 100, 3)).append(" ").append(num(p[1] * 100, 3));
            d.append(" C").append(num(p[2] * 100, 3)).append(" ").append(num(p[3] * 100, 3))
                    .append(" ").append(num(p[4] * 100, 3)).append(" ").append(num(p[5] * 100, 3))
                    .append(" ").append(num(p[6] * 100, 3)).append(" ").append(num(p[7] * 100, 3));
        }
        d.append(" Z");
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\" width=\"100\" height=\"100\">"
                + "<path d=\"" + d + "\"/></svg>\n";
    }

    static String bounds(float[] b) {
        return "[" + num(b[0], 5) + "," + num(b[1], 5) + "," + num(b[2], 5) + "," + num(b[3], 5) + "]";
    }

    /** LoadingIndicator.calculateScaleFactor: min over polygons of max(w/maxW, h/maxH). */
    static float scaleFactor(List<RoundedPolygon> polys) {
        float f = 1f;
        for (RoundedPolygon p : polys) {
            float[] b = p.calculateBounds(new float[4]);
            float[] mb = p.calculateMaxBounds(new float[4]);
            f = Math.min(f, Math.max((b[2] - b[0]) / (mb[2] - mb[0]), (b[3] - b[1]) / (mb[3] - mb[1])));
        }
        return f;
    }

    public static void main(String[] args) throws IOException {
        Path out = Path.of(args.length > 0 ? args[0] : ".");
        Map<String, RoundedPolygon> shapes = materialShapes();
        if (shapes.size() != 35) throw new IllegalStateException("expected 35 shapes, got " + shapes.size());

        // shapes.json + svg/
        Files.createDirectories(out.resolve("svg"));
        StringBuilder j = new StringBuilder();
        j.append("{\n  \"source\": {\n")
                .append("    \"repo\": \"https://github.com/androidx/androidx\",\n")
                .append("    \"commit\": \"").append(COMMIT).append("\",\n")
                .append("    \"file\": \"compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/MaterialShapes.kt\",\n")
                .append("    \"graphicsShapes\": \"androidx.graphics:graphics-shapes:1.0.1\"\n  },\n")
                .append("  \"space\": \"unit square [0,1]x[0,1], y down (Compose/SVG), post RoundedPolygon.normalized()\",\n")
                .append("  \"cubic\": \"[anchor0x, anchor0y, control0x, control0y, control1x, control1y, anchor1x, anchor1y]\",\n")
                .append("  \"shapes\": {\n");
        int n = 0;
        for (var e : shapes.entrySet()) {
            List<Cubic> cubics = e.getValue().getCubics();
            j.append("    \"").append(e.getKey()).append("\": {\n")
                    .append("      \"center\": [").append(num(e.getValue().getCenterX(), 5)).append(",")
                    .append(num(e.getValue().getCenterY(), 5)).append("],\n")
                    .append("      \"bounds\": ").append(bounds(e.getValue().calculateBounds(new float[4]))).append(",\n")
                    .append("      \"cubics\": ").append(cubicsJson(cubics, "      ")).append("\n    }")
                    .append(++n < shapes.size() ? ",\n" : "\n");
            Files.writeString(out.resolve("svg").resolve(e.getKey() + ".svg"), svg(cubics));
        }
        j.append("  }\n}\n");
        Files.writeString(out.resolve("shapes.json"), j.toString());

        // morphs.json
        String[] indet = {"soft-burst", "cookie-9-sided", "pentagon", "pill", "sunny", "cookie-4-sided", "oval"};
        List<RoundedPolygon> indetPolys = new ArrayList<>();
        for (String s : indet) indetPolys.add(shapes.get(s));
        // DeterminateIndicatorPolygons: Circle rotated by 360/20 degrees, then SoftBurst.
        RoundedPolygon circleRot = transformed(shapes.get("circle"), new Mat().rotateZ(360f / 20));
        List<RoundedPolygon> detPolys = List.of(circleRot, shapes.get("soft-burst"));
        float activeScale = 38f / Math.min(48f, 48f);

        StringBuilder m = new StringBuilder();
        m.append("{\n  \"source\": {\n")
                .append("    \"commit\": \"").append(COMMIT).append("\",\n")
                .append("    \"file\": \"compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/LoadingIndicator.kt\"\n  },\n")
                .append("  \"lerp\": \"cubic(t)[k] = start[i][k] + (end[i][k] - start[i][k]) * t; draw cubics in order as one closed path\",\n")
                .append("  \"notes\": [\n")
                .append("    \"Pairs are Morph(a.normalized(), b.normalized()) from graphics-shapes 1.0.1; start = asCubics(0f), end = asCubics(1f).\",\n")
                .append("    \"LoadingIndicator draws the morph path with startAngle = 0 (no path rotation), scales it by containerSize * scaleFactor, then translates so the path's bounds center sits on the container center (every frame).\",\n")
                .append("    \"scaleFactor = calculateScaleFactor(polygons) * ActiveIndicatorScale; ActiveIndicatorScale = IndicatorSize 38dp / min(ContainerWidth 48dp, ContainerHeight 48dp).\",\n")
                .append("    \"Indeterminate: morphProgress animates 0->1 with spring(dampingRatio 0.6, stiffness 200, visibilityThreshold 0.1) every 650 ms (MorphIntervalMillis); on finish index = (index+1) % 7, progress snaps to 0, morphRotationTargetAngle = (angle + 90) % 360 (initial 90). Draw rotation (degrees, clockwise, about container center) = progress*90 + morphRotationTargetAngle + globalRotation; globalRotation runs 0->360 linearly over 4666 ms, repeating.\",\n")
                .append("    \"Determinate: sequence is not circular (1 morph). activeIndex = min(floor(n*progress), n-1); morph progress = (progress*n) % 1 (1 at progress 1). Draw rotation = -progress*180 degrees (counter-clockwise).\",\n")
                .append("    \"Other material3 shape animation: button/icon-button press and toggle shapes (internal/AnimatedShape.kt) animate CornerBasedShape corner sizes, not RoundedPolygon Morphs; foundation MorphPolygonShape is a generic Shape wrapper. Only LoadingIndicator morphs MaterialShapes in material3 commonMain; those pairs are the only ones exported.\"\n")
                .append("  ],\n");
        m.append("  \"indeterminate\": ");
        appendSequence(m, indet, indetPolys, true, scaleFactor(indetPolys), activeScale);
        m.append(",\n  \"determinate\": ");
        appendSequence(m, new String[] {"circle-rotated-18deg", "soft-burst"}, detPolys, false,
                scaleFactor(detPolys), activeScale);
        m.append("\n}\n");
        Files.writeString(out.resolve("morphs.json"), m.toString());

        verify(shapes, indetPolys, detPolys);
        System.out.println("wrote " + shapes.size() + " shapes, morphs to " + out.toAbsolutePath());
    }

    static void appendSequence(StringBuilder m, String[] names, List<RoundedPolygon> polys, boolean circular,
                               float scale, float activeScale) {
        m.append("{\n    \"sequence\": [");
        for (int i = 0; i < names.length; i++) m.append(i == 0 ? "\"" : ", \"").append(names[i]).append("\"");
        m.append("],\n    \"circular\": ").append(circular).append(",\n")
                .append("    \"shapesScaleFactor\": ").append(num(scale, 5)).append(",\n")
                .append("    \"activeIndicatorScale\": ").append(num(activeScale, 5)).append(",\n")
                .append("    \"drawScale\": ").append(num(scale * activeScale, 5)).append(",\n")
                .append("    \"pairs\": [\n");
        int count = circular ? names.length : names.length - 1;
        for (int i = 0; i < count; i++) {
            int k = (i + 1) % names.length;
            Morph morph = new Morph(polys.get(i).normalized(), polys.get(k).normalized());
            List<Cubic> a = morph.asCubics(0f), b = morph.asCubics(1f);
            if (a.size() != b.size()) throw new IllegalStateException("unequal morph lengths");
            m.append("      {\n        \"from\": \"").append(names[i]).append("\",\n")
                    .append("        \"to\": \"").append(names[k]).append("\",\n")
                    .append("        \"start\": ").append(cubicsJson(a, "        ")).append(",\n")
                    .append("        \"end\": ").append(cubicsJson(b, "        ")).append("\n      }")
                    .append(i + 1 < count ? ",\n" : "\n");
        }
        m.append("    ]\n  }");
    }

    // ---- Verification --------------------------------------------------------

    /** Checks each morph's t=0 / t=1 outline lies on the source / target outline. */
    static void verify(Map<String, RoundedPolygon> shapes, List<RoundedPolygon> indet, List<RoundedPolygon> det) {
        List<List<RoundedPolygon>> seqs = List.of(indet, det);
        for (int s = 0; s < 2; s++) {
            List<RoundedPolygon> seq = seqs.get(s);
            int count = s == 0 ? seq.size() : seq.size() - 1;
            for (int i = 0; i < count; i++) {
                RoundedPolygon a = seq.get(i).normalized(), b = seq.get((i + 1) % seq.size()).normalized();
                Morph morph = new Morph(a, b);
                List<Cubic> c0 = morph.asCubics(0f), c1 = morph.asCubics(1f);
                double d0 = maxDist(c0, a.getCubics()), d1 = maxDist(c1, b.getCubics());
                System.out.printf(Locale.ROOT, "verify %s pair %d: %d cubics, start->from %.2e, end->to %.2e%n",
                        s == 0 ? "indeterminate" : "determinate", i, c0.size(), d0, d1);
                if (c0.size() != c1.size() || d0 > 2e-3 || d1 > 2e-3) throw new IllegalStateException("morph verify failed");
            }
        }
    }

    static float[] eval(float[] p, float t) {
        float u = 1 - t;
        float a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
        return new float[] {a * p[0] + b * p[2] + c * p[4] + d * p[6], a * p[1] + b * p[3] + c * p[5] + d * p[7]};
    }

    static double maxDist(List<Cubic> probe, List<Cubic> ref) {
        List<float[]> refPts = new ArrayList<>();
        for (Cubic c : ref) for (int k = 0; k <= 400; k++) refPts.add(eval(pts(c), k / 400f));
        double worst = 0;
        for (Cubic c : probe) {
            for (int k = 0; k <= 16; k++) {
                float[] q = eval(pts(c), k / 16f);
                double best = Double.MAX_VALUE;
                for (float[] r : refPts) best = Math.min(best, Math.hypot(q[0] - r[0], q[1] - r[1]));
                worst = Math.max(worst, best);
            }
        }
        return worst;
    }
}
