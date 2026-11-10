# Glyph orientation and baseline convention

This note defines the text-coordinate contract for US-013. It records the current
data path and the evidence available; it does not change either renderer or
declare a backend incorrect.

## Data and coordinate contract

`stbtt_GetGlyphBitmap` returns a tightly packed, single-channel 8-bit bitmap
stored left-to-right and top-to-bottom. Its `xoff` and `yoff` locate the
bitmap's **top-left** relative to the glyph origin. The glyph origin passed to
the renderer is on the baseline. In particular, `yoff` is in stb's
bitmap-coordinate convention, not a positive-up distance.

`CGFont.rasterizedGlyph` copies those bytes in order into `CGGlyphBitmap`.
`CGGlyphAtlas` copies each bitmap row unchanged into a row-major atlas, with
the first stored row at `atlasY`; its one-pixel leading gutter is transparent.
Consequently, atlas row `atlasY` is the glyph's top row, and increasing atlas
row numbers move down through the stb bitmap.

Use a logical text/device coordinate system with +x to the right and +y upward.
For a glyph at text-space baseline position `(px, py)`, bitmap dimensions
`(w, h)`, and bearings `(xoff, yoff)`, its quad is:

```text
left   = px + xoff
right  = left + w
top    = py - yoff
bottom = py - (yoff + h)
```

The four corners are ordered bottom-left, bottom-right, top-right, top-left.
This converts stb's top-down bitmap placement into a baseline-based,
y-up quad. A negative `yoff` places the top above the baseline; a positive
`yoff + h` places the bottom below it.

For glyph index `i`, text-space character spacing is added to the baseline x
position before applying `textMatrix`. The transform order implemented by both
text paths is:

```text
localPoint = (positions[i].x + i * characterSpacing, positions[i].y)
             + glyphBearingAndQuadCorner
userPoint  = textMatrix(localPoint) + textPosition
devicePoint = CTM(userPoint)
```

Thus `textPosition` is a user-space translation: it is not transformed by
`textMatrix`, but it is transformed by the CTM. Rotation and either sign of
scale apply to the entire glyph quad. Spacing is horizontal in text space, so
the text matrix may rotate or scale its resulting displacement.

## Atlas and OpenGL mapping

OpenGL uploads `CGGlyphAtlas.coverage` unchanged as a one-channel texture.
Texture coordinate `v = 0` addresses the first uploaded row. The GL glyph quad
uses `v = (atlasY + height) / atlasHeight` on its lower edge and
`v = atlasY / atlasHeight` on its upper edge. Its UV corner order is therefore:

| Quad corner | UV |
|---|---|
| bottom-left | `(atlasX / atlasWidth, (atlasY + height) / atlasHeight)` |
| bottom-right | `((atlasX + width) / atlasWidth, (atlasY + height) / atlasHeight)` |
| top-right | `((atlasX + width) / atlasWidth, atlasY / atlasHeight)` |
| top-left | `(atlasX / atlasWidth, atlasY / atlasHeight)` |

This assigns the first stb row to the geometric top of the glyph while leaving
the atlas bytes in stb order. The six GL vertices use corners
`[bottom-left, bottom-right, top-right, bottom-left, top-right, top-left]`.

The software path uses the same quad corners and inverse-maps each destination
pixel to the atlas. Its row selection must be tested against the same
top-to-bottom source-row contract; do not infer parity from matching quad
bounds alone.

## Asymmetric 2×3 reference mask

Use this exact source mask, with rows listed in stb storage order (top to
bottom):

```text
row 0 (top):     255   32
row 1:            64  192
row 2 (bottom):  128    0
```

For one bitmap of `width = 2`, `height = 3`, `xOffset = 1`, the current packer
produces a `5×5` atlas: the glyph starts at `(atlasX, atlasY) = (1, 1)`, and its
coverage bytes by atlas row are:

```text
0 0   0   0 0
0 255 32  0 0
0 64  192 0 0
0 128 0   0 0
0 0   0   0 0
```

The glyph UV bounds are left `1/5`, right `3/5`, top `1/5`, bottom `4/5`.
At a baseline `B = (10, 10)`:

* With `yOffset = -3`, the quad is x `[11, 13]`, y `[10, 13]`. The expected
  coverage is `(11,12)=255`, `(12,12)=32`, `(11,11)=64`, `(12,11)=192`,
  `(11,10)=128`, `(12,10)=0`. The top row is above the baseline; the bottom
  row's lower edge meets it.
* With `yOffset = 0`, the quad is x `[11, 13]`, y `[7, 10]`. The expected
  coverage is `(11,9)=255`, `(12,9)=32`, `(11,8)=64`, `(12,8)=192`,
  `(11,7)=128`, `(12,7)=0`. The top row's upper edge meets the baseline and
  the remaining rows are below it.

The coordinates above refer to context/device pixel indices, not to the
visual top-down ordering of a screenshot. Render onto a transparent surface
with white glyph color and compare the exact coverage (the resulting alpha
channel) at those indices, plus untouched pixels immediately outside both
quads. Sample at pixel centers so filtering cannot blur the expected values.

For the GL case, the first quad's UVs in the six-vertex order above are:

```text
(1/5,4/5), (3/5,4/5), (3/5,1/5),
(1/5,4/5), (3/5,1/5), (1/5,1/5)
```

## Test specification

The follow-up pixel tests should use the synthetic mask above rather than a
font glyph whose rows may be identical. They should verify:

1. **Bitmap and atlas:** exact dimensions, bearings, row-major coverage bytes,
   atlas origin, transparent gutter, and the UV/quad values shown above.
2. **Baseline and pixel orientation:** the exact coverage values and coordinates
   for both `yOffset` cases; also assert that transparent neighbors and the
   baseline-side pixels not covered by the mask remain unchanged.
3. **`textMatrix`, `textPosition`, and CTM order:** use the upper mask with
   baseline `(2,3)`, `textMatrix` equal to a 90° counter-clockwise rotation
   (`a=0, b=1, c=-1, d=0`), `textPosition=(10,20)`, and CTM equal to scale 2
   followed by translation `(5,7)`. The untransformed quad corners are
   `BL=(3,3)`, `BR=(5,3)`, `TR=(5,6)`, `TL=(3,6)`; expected device corners are
   `BL=(19,53)`, `BR=(19,57)`, `TR=(13,57)`, `TL=(13,53)`. This distinguishes
   the order and whether text position is transformed by the text matrix.
4. **Spacing:** with baselines `(2,3)` and `(8,3)`, spacing `3`, horizontal
   text-matrix scale `2`, and identity CTM, the transformed baseline-origin
   separation is `18` units. This proves spacing is inserted before the text
   matrix and scales with it.
5. **Rotation and negative scale:** verify exact output pixels after a 90°
   rotation and after horizontal and vertical reflections. For a horizontal
   CTM reflection `x' = 20 - x`, the mask at x `[11,13]` moves to `[7,9]`
   and its two columns exchange positions. A vertical reflection must exchange
   the top and bottom source rows. Do not compare only bounding boxes.
6. **Cross-backend observation:** execute the same asymmetric input through
   software and real GL, inspect per-pixel coverage and representative
   coordinates, and retain the GL dimensions/readback orientation. A global
   mean alone cannot establish glyph orientation.

## Existing observation and limits

On 2026-11-10, the opt-in real-GL test was run with:

```sh
OPENCOREGRAPHICS_RUN_GL_COMPARISON=1 swift test --filter GLGlyphComparisonTests
```

It passed with `difference=0.0` and tolerance `4/255`. This is a real
cross-backend observation, but it does not settle row orientation: the bundled
`tiny-test.ttf` was rasterized through the same stb wrapper, and its tested `I`
mask is `2×14` with every sample `255`, while its `A` mask is `8×14` with every
sample `255`. Reversing either mask's rows produces identical bytes. The test
also checks mean difference rather than exact asymmetric pixels.

Source inspection shows that GL flips the vertical UV assignment relative to
the stored row order, while the software sampler indexes stored atlas rows as
its local vertical coordinate increases from the quad's lower edge. This makes
the synthetic test above necessary to resolve the mapping against actual
readback. The existing all-opaque fixture neither proves nor disproves the
suspected difference, so this specification does **not** label either backend
incorrect or authorize changing its behavior.
