import SwiftUI

struct FloatingPanelView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var transcriptionService: TranscriptionService

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if transcriptionService.isRecording {
                    HStack(spacing: 6) {
                        RecordingDot()
                        Text("REC \(transcriptionService.formattedDuration)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.echoDanger)
                    }
                } else {
                    Text("待機中")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.echoTextSecondary)
                }

                Spacer()

                if transcriptionService.isRecording {
                    WaveformIcon(animated: true, targetFPS: 12)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { EchoDivider() }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    let lines = transcriptionService.isRecording ? transcriptionService.liveLines : []

                    if lines.isEmpty {
                        Text(transcriptionService.isRecording
                             ? (transcriptionService.isCapturingSystemAudio
                                ? "発言を待機中…（A＝自分 / B〜＝参加者）"
                                : "発言を待機中…")
                             : "文字起こしを開始するとここに表示されます")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.echoTextTertiary)
                    } else {
                        ForEach(lines) { line in
                            TranscriptLineView(line: line)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .frame(maxHeight: 150)
        }
        .frame(width: 260)
        .background {
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                Color.echoBgPanelTranslucent
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: EchoRadius.card, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: EchoRadius.card, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 12)
        .overlay(alignment: .bottom) {
            if let message = appState.bannerMessage ?? transcriptionService.lastErrorMessage {
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(8)
            }
        }
    }
}

struct TranscriptLineView: View {
    let line: TranscriptLine

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            SpeakerTag(speaker: line.speaker)

            Text(line.text)
                .font(.system(size: 12.5))
                .foregroundStyle(line.isDimmed ? Color.echoTextTertiary : Color.echoTextPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SpeakerTag: View {
    let speaker: Speaker

    var body: some View {
        Text(speaker.label)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(speaker.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(speaker.color.opacity(speaker.isSelf ? 0.12 : 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// デザイン仕様のデスクトップ背景モック（プレビュー用）
struct FloatingPanelPreviewContainer: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: EchoRadius.window, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.114, green: 0.169, blue: 0.329),
                            Color(red: 0.055, green: 0.090, blue: 0.188)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 340)

            Text("Floating Panel Preview")
                .padding()
        }
        .clipShape(RoundedRectangle(cornerRadius: EchoRadius.window, style: .continuous))
    }
}
