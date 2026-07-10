import SwiftUI

struct WaveformIcon: View {
    var animated = true
    /// メニューバー用: 外部から低頻度で時刻を渡すと TimelineView を使わず安全にアニメーションできる
    var externalTime: TimeInterval?
    var targetFPS: Double = 60

    private let barHeights: [CGFloat] = [0.4, 1.0, 0.6, 0.9, 0.5, 0.75]
    private let delays: [Double] = [0, 0.1, 0.2, 0.3, 0.4, 0.5]

    var body: some View {
        if animated, externalTime == nil {
            TimelineView(.animation(minimumInterval: 1.0 / targetFPS)) { timeline in
                waveform(at: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            waveform(at: externalTime ?? 0)
        }
    }

    private func waveform(at time: TimeInterval) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<6, id: \.self) { index in
                WaveformBar(
                    baseHeight: barHeights[index],
                    time: time,
                    delay: delays[index]
                )
            }
        }
        .frame(height: 16)
    }
}

private struct WaveformBar: View {
    let baseHeight: CGFloat
    let time: TimeInterval
    let delay: Double

    private let period: Double = 1.2

    var body: some View {
        let phase = (time + delay).truncatingRemainder(dividingBy: period) / period
        let scale = 0.5 + 0.5 * sin(phase * 2 * .pi)
        let height = max(2, 16 * baseHeight * scale)

        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.echoAccent, .echoAccentTeal],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 2.5, height: height)
            .frame(height: 16, alignment: .bottom)
    }
}

#Preview {
    WaveformIcon()
        .padding()
}
