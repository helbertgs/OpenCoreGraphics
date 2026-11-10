# Color-Space Conversion

`CGColor.converted(to:)` is the shared conversion point for sRGB and linear RGB. It uses the standard piecewise sRGB transfer functions, preserves alpha, returns the original color when the spaces match, and returns `nil` for unsupported conversions.

The software renderer converts color and image samples into linear RGB before compositing. When a bitmap surface uses sRGB, it converts the completed premultiplied pixel back to sRGB before storing it.

The OpenGL renderer converts solid colors and uploaded sRGB texture pixels into linear RGB. Window creation requests an sRGB-capable default framebuffer, then checks the actual `GL_BACK_LEFT` attachment encoding after GLAD loads. `GL_FRAMEBUFFER_SRGB` is enabled only for an sRGB attachment; it remains disabled for a linear attachment, preventing an implicit second conversion.

The sRGB capability hint is advisory. If the driver supplies a linear framebuffer instead, rendering continues with linear values and no framebuffer conversion.
