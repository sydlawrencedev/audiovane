import AppKit
import CoreGraphics

/// The Vibresia wave: the shape of the logo, in one place.
///
/// It is drawn three ways — as a canvas in the app's header, as the mark on a
/// share image, and as an SVG path on the website — and all three have to be
/// the same shape. A logo redrawn by hand in each place is a logo that drifts
/// apart, and then the app and its own share pictures stop looking like the
/// same product.
///
/// So the shape lives here, and everything else is a way of drawing it.
public enum BrandWave {
    /// The points of the wave in a unit box. x runs left to right and y runs
    /// top to bottom, the way a canvas draws.
    ///
    /// It is a heartbeat line that never quite settles: flat, a spike up, a
    /// spike down, and back to flat again.
    public static let points: [CGPoint] = [
        CGPoint(x: 0.00, y: 0.50),
        CGPoint(x: 0.22, y: 0.50),
        CGPoint(x: 0.32, y: 0.20),
        CGPoint(x: 0.45, y: 0.80),
        CGPoint(x: 0.58, y: 0.30),
        CGPoint(x: 0.70, y: 0.65),
        CGPoint(x: 0.78, y: 0.50),
        CGPoint(x: 1.00, y: 0.50),
    ]

    /// The same wave as an SVG path in a 32-unit box — the shape the
    /// website's favicon and its header use.
    ///
    /// Inset by 1.6 units at each end so the stroke has room: a 32-unit box
    /// with a wave that starts at 0 has half its stroke outside the box, and
    /// the favicon is drawn from that box.
    public static let svgPath =
        "M1.6 16 L7.94 16 L10.82 6.4 L14.56 25.6 L18.3 9.6 L21.76 20.8 L24.06 16 L30.4 16"

    /// The wave as a path in a rect.
    ///
    /// CoreGraphics counts y from the bottom and the points above count from
    /// the top, so the y is flipped on the way through.
    public static func path(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        for (index, point) in points.enumerated() {
            let q = CGPoint(x: rect.minX + point.x * rect.width,
                            y: rect.maxY - point.y * rect.height)
            index == 0 ? path.move(to: q) : path.addLine(to: q)
        }
        return path
    }
}

/// How Vibresia draws itself on a picture.
///
/// The mark and the wordmark in the top-left corner, the credit in the
/// bottom-right, and a soft wash behind both so they survive a bright frame.
///
/// This is the app's share image and the website's built-in share graphics,
/// and they use the same code: the built-in pictures used to be drawn by a
/// build script with its own copy of the logo, which is how the two ended up
/// looking like different products.
public enum ShareImageBrand {
    /// The app's accent magenta.
    public static let magenta = NSColor(red: 1, green: 0.17, blue: 0.84, alpha: 1)
    /// The lighter magenta in the middle of the mark, so it reads as neon
    /// rather than as a pink line.
    public static let magentaSoft = NSColor(red: 1, green: 0.78, blue: 0.96, alpha: 1)
    /// The credit's colour.
    public static let gold = NSColor(red: 1, green: 0.76, blue: 0.35, alpha: 1)

    /// The edge the brand and the credit sit against.
    private static let margin: CGFloat = 30
    /// The height of the mark.
    private static let markSize: CGFloat = 30
    /// The gap between the mark and the wordmark.
    private static let markGap: CGFloat = 12

    /// The brand, in the top-left: the mark with the wordmark right beside
    /// it.
    public static func drawBrand(in ctx: CGContext, size: CGSize) {
        let originX = margin + 4
        let originY = size.height - margin - 4 - markSize

        let markRect = CGRect(x: originX, y: originY, width: markSize, height: markSize)
        drawMark(ctx, in: markRect)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 19, weight: .bold),
            .foregroundColor: NSColor.white,
            .kern: 3.4,
            .shadow: textShadow(),
        ]
        let wordmark = NSAttributedString(string: "VIBRESIA", attributes: attrs)
        let textSize = wordmark.size()
        wordmark.draw(at: CGPoint(x: originX + markSize + markGap,
                                  y: originY + (markSize - textSize.height) / 2))
    }

    /// The credit, in the bottom-right.
    public static func drawCredit(in ctx: CGContext, size: CGSize, author: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .regular),
            .foregroundColor: gold,
            .shadow: textShadow(),
        ]
        let credit = NSAttributedString(
            string: "Made with ❤️ by \(author)", attributes: attrs)
        let textSize = credit.size()
        credit.draw(at: CGPoint(x: size.width - textSize.width - margin,
                                y: margin + 4))
    }

    /// A soft dark shadow behind the lettering.
    ///
    /// The wash in the corner is not enough on its own: a vibescape can put a
    /// stage light right where the credit goes, and gold on white is not a
    /// thing anybody can read. The shadow separates the letters from whatever
    /// is behind them without drawing a box around them.
    private static func textShadow() -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.85)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = .zero
        return shadow
    }

    /// The mark on its own: a magenta line with a glow, and a hot core so it
    /// reads as neon rather than as a pink line.
    public static func drawMark(_ ctx: CGContext, in rect: CGRect) {
        let path = BrandWave.path(in: rect)
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setShadow(offset: .zero, blur: 12,
                      color: magenta.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(max(2, rect.width * 0.085))
        ctx.setStrokeColor(magenta.cgColor)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()

        ctx.setLineWidth(max(1, rect.width * 0.032))
        ctx.setStrokeColor(magentaSoft.cgColor)
        ctx.addPath(path)
        ctx.strokePath()
    }

    /// A soft dark wash in a corner.
    ///
    /// A vibescape can be anything: a bright stage, a white flash, a neon
    /// corridor. Without something behind them the white wordmark and the gold
    /// credit disappear into it, and the picture is the thing people look at —
    /// so the brand gets a corner to itself.
    ///
    /// `strength` is how dark the corner gets at its darkest, which is
    /// different for the two corners: the credit sits where a stage light is
    /// most likely to be, so it gets more.
    public static func drawScrim(in ctx: CGContext, corner: CGPoint, radius: CGFloat,
                                  strength: CGFloat = 0.58) {
        let colors = [NSColor(white: 0, alpha: strength).cgColor,
                      NSColor(white: 0, alpha: 0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: [0, 1]) else { return }
        ctx.drawRadialGradient(gradient, startCenter: corner, startRadius: 0,
                               endCenter: corner, endRadius: radius,
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// The brand and the credit over a picture, with the scrims behind them.
    public static func draw(in ctx: CGContext, size: CGSize, author: String) {
        drawScrim(in: ctx, corner: CGPoint(x: 4, y: size.height - 4), radius: 190)
        drawScrim(in: ctx, corner: CGPoint(x: size.width - 4, y: 4),
                  radius: 320, strength: 0.72)
        drawBrand(in: ctx, size: size)
        drawCredit(in: ctx, size: size, author: author)
    }

    /// A copy of an image with the brand and the credit on it.
    ///
    /// The scrims go on first, then the brand, so the mark sits on top of the
    /// wash rather than under it.
    ///
    /// The drawing goes through an `NSGraphicsContext` rather than the bare
    /// CoreGraphics one: AppKit draws text through the current graphics
    /// context, and with only a CGContext there isn't one, so the wordmark
    /// and the credit silently don't appear.
    public static func branded(_ image: CGImage, author: String) -> CGImage? {
        let width = image.width
        let height = image.height
        guard let ctx = CGContext(data: nil,
                                  width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Not flipped: CoreGraphics counts y from the bottom, which is where
        // the credit and the mark are measured from.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        draw(in: ctx, size: CGSize(width: width, height: height), author: author)
        NSGraphicsContext.restoreGraphicsState()

        return ctx.makeImage()
    }
}
