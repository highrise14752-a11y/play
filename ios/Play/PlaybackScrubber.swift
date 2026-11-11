// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct PlaybackScrubber: View {
    @Binding var preview: Double?
    let position: Double
    let duration: Double
    let seek: (Double) -> Void
    @AppStorage("appearance.sliderStyle") private var style = "Standard"

    private var fraction: Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(1, max(0, (preview ?? position) / duration))
    }

    var body: some View {
        if style == "Standard" {
            Slider(value: Binding(get: { min(max(1, duration), preview ?? position) }, set: { preview = $0 }),
                   in: 0...max(1, duration)) { editing in
                if !editing, let value = preview { seek(value); preview = nil }
            }.disabled(duration <= 0).accessibilityLabel("Playback position")
        } else {
            GeometryReader { geometry in
                Canvas { context, size in
                    drawTrack(context, size: size)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { if duration > 0 { preview = value(at: $0.location.x, width: geometry.size.width) } }
                    .onEnded {
                        if duration > 0 { seek(value(at: $0.location.x, width: geometry.size.width)) }
                        preview = nil
                    })
            }
            .frame(height: 36)
            .accessibilityLabel("Playback position")
            .accessibilityValue(TrackTime.text(preview ?? position, elapsed: true))
            .accessibilityAdjustableAction { direction in
                guard duration > 0 else { return }
                switch direction {
                case .increment: seek(min(duration, position + 10))
                case .decrement: seek(max(0, position - 10))
                @unknown default: break
                }
            }
        }
    }

    private func value(at x: CGFloat, width: CGFloat) -> Double {
        Double(min(1, max(0, x / max(1, width)))) * duration
    }

    private func drawTrack(_ context: GraphicsContext, size: CGSize) {
        let end = size.width * CGFloat(fraction)
        let y = size.height / 2
        let muted = Color.secondary.opacity(0.26)
        let accent = PlayTheme.accent
        if style == "Wavy" {
            func wave(to end: CGFloat) -> Path {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    for x in stride(from: CGFloat(0), through: end, by: 2) {
                        path.addLine(to: CGPoint(x: x, y: y + sin(x * 0.28) * 3))
                    }
                }
            }
            context.stroke(wave(to: size.width), with: .color(muted), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            context.stroke(wave(to: end), with: .color(accent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        } else {
            let thickness: CGFloat = style == "Thick" ? 8 : 2
            let track = CGRect(x: 0, y: y - thickness / 2, width: size.width, height: thickness)
            context.fill(Path(roundedRect: track, cornerRadius: thickness / 2), with: .color(muted))
            if end > 0 {
                let played = CGRect(x: 0, y: track.minY, width: end, height: thickness)
                context.fill(Path(roundedRect: played, cornerRadius: thickness / 2), with: .color(accent))
            }
            if style == "Circular" {
                let center = min(max(7, end), max(7, size.width - 7))
                context.fill(Path(ellipseIn: CGRect(x: center - 7, y: y - 7, width: 14, height: 14)), with: .color(accent))
            }
        }
    }
}
