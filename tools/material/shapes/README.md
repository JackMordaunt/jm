# Material 3 Expressive shapes

Compose `MaterialShapes` (all 35) and the `LoadingIndicator` morphs, as plain cubic Béziers.
Source: androidx `1358a48e9c23e257ae3357f6f645cb60a3610a7f` and `graphics-shapes` 1.0.1, the version material3 pins.

## Files

- `shapes.json`: `shapes.<name>.cubics` is a list of `[x0,y0, c1x,c1y, c2x,c2y, x1,y1]` (anchor, control, control, anchor), rounded to 5 decimals. Each shape also records its `center` and `bounds`. Names are the Compose property names in kebab case, e.g. `Cookie4Sided` becomes `cookie-4-sided`.
- `svg/<name>.svg`: the same path as an SVG with `viewBox="0 0 100 100"`, where coordinates are ×100.
- `morphs.json`: the pairs precomputed by `Morph(a, b)` for the indeterminate sequence (7 pairs, including the wrap from oval back to soft-burst) and the determinate sequence (1 pair). Each pair has `start` = `asCubics(0)` and `end` = `asCubics(1)`, and both lists have equal length. `notes` holds the timing, rotation and scaling rules.
- `contact-sheet.png`: all 35 SVGs rasterised, for eyeballing.
- `gen/`: the generator. It is a Java port of `MaterialShapes.kt` that runs against the real graphics-shapes jar.

## Coordinate space

The unit square [0,1]², y down, with the origin at the top-left, which is the space Compose and SVG draw in. The data is post-`RoundedPolygon.normalized()`: the longer side spans 0..1 and the shorter side is centred.
`toShape()` scales this by the component size and centres the path's bounds. Shapes are drawn with `startAngle = 0`, so no extra rotation is applied.

## Rendering

For each shape, `moveTo(c[0].x0, c[0].y0)`, then `cubicTo(c1, c2, p1)` for every cubic, then close the path. Fill with the non-zero rule.
Each cubic's end point equals the next cubic's start point, and the last cubic returns to the first point.

## Morphing

Morph matching is the expensive part of graphics-shapes, because it measures and splits features to pair them up. That work is already done here, so no matching runs at runtime.
The morphed shape is just `cubic(t)[i][k] = start[i][k] + (end[i][k] - start[i][k]) * t`, drawn like a shape.
The `t` value comes from a spring and can overshoot 1. Compose passes that raw value through.

LoadingIndicator also rotates the shape, scales it by `drawScale` (per sequence) × the container size, and re-centres it every frame. See `morphs.json` → `notes` for the exact rules.

## Regenerate

```sh
gen/run.sh            # needs java >= 21 + curl; fetches 4 jars, rewrites shapes.json, morphs.json, svg/
```

The generator also checks that every morph endpoint lies within 1e-3 of its source outline. It throws if a check fails.
