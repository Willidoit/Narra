import SwiftUI

struct WaveformView: View {
    let levels: [Float]

    var body: some View {
        Canvas { context, size in
            let count = levels.count
            guard count > 0 else { return }
            let barWidth = size.width / CGFloat(count)
            let spacing: CGFloat = 2
            let actualBarWidth = max(1, barWidth - spacing)
            let centerY = size.height / 2

            for (i, level) in levels.enumerated() {
                let x = CGFloat(i) * barWidth + spacing / 2
                let barHeight = max(2, CGFloat(level) * size.height * 0.9)
                let rect = CGRect(
                    x: x,
                    y: centerY - barHeight / 2,
                    width: actualBarWidth,
                    height: barHeight
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: actualBarWidth / 2),
                    with: .linearGradient(
                        Gradient(colors: Iridescence.stops),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: size.width, y: 0)
                    )
                )
            }
        }
        .animation(.linear(duration: 0.05), value: levels)
        .frame(height: 60)
    }
}
