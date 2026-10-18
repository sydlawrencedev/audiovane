import SwiftUI

struct MeterView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        // Subscribe to the audio engine's display tick so the canvas only
        // re-evaluates when there's actually new data (~30Hz), not 60Hz from
        // TimelineView's per-frame schedule.
        let _ = app.audio.displayTick
        MeterCanvas(bands: app.audio.snapshot.bands,
                    isBeat: app.audio.snapshot.beat,
                    beatStrength: app.audio.snapshot.beatStrength)
    }
}

private struct MeterCanvas: View {
    let bands: [Float]
    let isBeat: Bool
    let beatStrength: Float

    var body: some View {
        Canvas { ctx, size in
            guard !bands.isEmpty else { return }

            let meterBands = 64
            let binStep = max(1, bands.count / meterBands)
            let barWidth = size.width / CGFloat(meterBands)
            let maxH = size.height

            // background grid
            ctx.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(.white.opacity(0.02))
            )

            for i in 0..<meterBands {
                let v1 = bands[i * binStep]
                let v2 = bands[min(bands.count - 1, (i + 1) * binStep)]
                let peak = max(v1, v2)
                let bh = min(maxH, CGFloat(peak) * maxH * 1.1)

                let x = CGFloat(i) * barWidth
                let rect = CGRect(x: x + 1, y: maxH - bh, width: barWidth - 2, height: bh)

                let color = bandColor(i: i, total: meterBands)
                drawBar(ctx: ctx, rect: rect, color: color, height: bh, maxH: maxH)
            }

            // beat flash overlay
            if beatStrength > 0.05 {
                let alpha = Double(beatStrength) * 0.18
                let overlayColor = Color(red: 1, green: 0.17, blue: 0.84).opacity(alpha)
                ctx.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(overlayColor)
                )
            }
        }
        .frame(width: 240, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func bandColor(i: Int, total: Int) -> Color {
        if i < total / 3 {
            return Color(red: 1, green: 0.17, blue: 0.84)
        } else if i < (total * 2) / 3 {
            return Color(red: 0.54, green: 0.30, blue: 1.0)
        } else {
            return Color(red: 0.17, green: 0.95, blue: 1.0)
        }
    }

    private func drawBar(ctx: GraphicsContext, rect: CGRect, color: Color, height: CGFloat, maxH: CGFloat) {
        let gradient = Gradient(stops: [
            .init(color: color.opacity(0.2), location: 0.0),
            .init(color: color, location: 1.0)
        ])
        let startY = CGPoint(x: 0, y: maxH)
        let endY = CGPoint(x: 0, y: maxH - height)
        ctx.fill(
            Path(rect),
            with: .linearGradient(gradient, startPoint: startY, endPoint: endY)
        )
    }
}