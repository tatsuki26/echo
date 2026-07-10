import SwiftUI

struct FloatingPanelView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if appState.isRecording {
                    HStack(spacing: 6) {
                        RecordingDot()
                        Text("REC \(appState.recordingDuration)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.echoDanger)
                    }
                } else {
                    Text("待機中")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.echoTextSecondary)
                }

                Spacer()

                if appState.isRecording {
                    WaveformIcon(animated: true, targetFPS: 60)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { EchoDivider() }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    let lines = appState.isRecording ? appState.liveTranscriptLines : []

                    if lines.isEmpty {
                        Text(appState.isRecording
                             ? (appState.transcriptionService.isCapturingSystemAudio
                                ? "発言を待機中…（話者A＝自分 / 話者B＝相手）"
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
            if let message = appState.bannerMessage ?? appState.transcriptionService.lastErrorMessage {
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
            .foregroundStyle(speaker == .a ? Color.echoSpeakerA : Color.echoSpeakerB)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                (speaker == .a ? Color.echoSpeakerA : Color.echoSpeakerB).opacity(speaker == .a ? 0.12 : 0.14)
            )
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
                .overlay {
                    RadialGradient(
                        colors: [Color(red: 0.290, green: 0.424, blue: 0.969).opacity(0.8), .clear],
                        center: UnitPoint(x: 0.3, y: 0.2),
                        startRadius: 0,
                        endRadius: 200
                    )
                }
                .overlay {
                    RadialGradient(
                        colors: [Color(red: 0.106, green: 0.165, blue: 0.369).opacity(0.9), .clear],
                        center: UnitPoint(x: 0.8, y: 0.8),
                        startRadius: 0,
                        endRadius: 220
                    )
                }
                .frame(height: 340)

            FloatingPanelView()
                .padding(.top, 20)
                .padding(.trailing, 20)
        }
        .clipShape(RoundedRectangle(cornerRadius: EchoRadius.window, style: .continuous))
    }
}
