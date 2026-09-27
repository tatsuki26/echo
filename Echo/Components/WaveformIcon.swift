import SwiftUI

struct WaveformIcon: View {
    var animated = true
    /// メニューバー用: 外部から低頻度で時刻を渡すと TimelineView を使わず安全にアニメーションできる
    var externalTime: TimeInterval?
    var targetFPS: Double = 60
    /// 実際の入力レベル（0...1）。指定するとサイン波ではなく音量に連動した波形を描く
    var levels: [CGFloat]?
    var tint: [Color] = [.echoAccent, .echoAccentTeal]

    private let barHeights: [CGFloat] = [0.4, 1.0, 0.6, 0.9, 0.5, 0.75]
    private let delays: [Double] = [0, 0.1, 0.2, 0.3, 0.4, 0.5]

    var body: some View {
        if let levels {
            levelWaveform(levels)
        } else if animated, externalTime == nil {
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
                    delay: delays[index],
                    tint: tint
                )
            }
        }
        .frame(height: 16)
    }

    private func levelWaveform(_ levels: [CGFloat]) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                // 中央のバーほど高くして、無音時も「待機中の平らな線」、発話時は山型に動く
                let shape = barHeights[index % barHeights.count]
                let height = max(2, 16 * min(1, level) * (0.55 + 0.45 * shape))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(LinearGradient(colors: tint, startPoint: .top, endPoint: .bottom))
                    .frame(width: 2.5, height: height)
                    .frame(height: 16, alignment: .center)
            }
        }
        .frame(height: 16)
    }
}

private struct WaveformBar: View {
    let baseHeight: CGFloat
    let time: TimeInterval
    let delay: Double
    let tint: [Color]

    private let period: Double = 1.2

    var body: some View {
        let phase = (time + delay).truncatingRemainder(dividingBy: period) / period
        let scale = 0.5 + 0.5 * sin(phase * 2 * .pi)
        let height = max(2, 16 * baseHeight * scale)

        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(
                LinearGradient(
                    colors: tint,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 2.5, height: height)
            .frame(height: 16, alignment: .bottom)
    }
}

/// フローティングパネル等で使う、入力レベルを直接ポーリングして描く波形。
struct LiveLevelWaveform: View {
    let meter: AudioLevelMeter
    var channel: AudioLevelMeter.Channel?
    var tint: [Color] = [.echoAccent, .echoAccentTeal]

    @State private var levels: [CGFloat] = Array(repeating: 0, count: MenuBarIconController.barCount)

    var body: some View {
        WaveformIcon(levels: levels, tint: tint)
            .onReceive(Timer.publish(every: 1.0 / 12.0, on: .main, in: .common).autoconnect()) { _ in
                let snapshot = meter.snapshot()
                let level: Float
                switch channel {
                case .mic: level = snapshot.micLevel
                case .system: level = snapshot.systemLevel
                case nil: level = snapshot.combinedLevel
                }
                var next = levels
                next.removeFirst()
                next.append(CGFloat(level))
                levels = next
            }
    }
}

#Preview {
    VStack {
        WaveformIcon()
        WaveformIcon(levels: [0, 0.2, 0.8, 1, 0.5, 0.1])
    }
    .padding()
}
