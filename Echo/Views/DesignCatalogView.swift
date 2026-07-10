import SwiftUI

/// デザイン仕様書セクション7に基づく4画面一覧プレビュー
struct DesignCatalogView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Echo — 会議文字起こしアプリ")
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.56)
                        .foregroundStyle(Color.echoTextPrimary)

                    Text("macOS向け会議文字起こしアプリのUIモックアップ。メニューバー常駐、フローティングパネル、履歴検索、会議詳細の4画面で構成。")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.echoTextSecondary)
                        .lineSpacing(6)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 320), spacing: 40)],
                    spacing: 40
                ) {
                    catalogItem(number: 1, label: "メニューバー") {
                        menuBarMock
                    }

                    catalogItem(number: 2, label: "会議中のフローティングパネル") {
                        FloatingPanelPreviewContainer()
                            .environmentObject(appState)
                    }

                    catalogItem(number: 3, label: "メインウィンドウ（履歴・検索）") {
                        HistoryListPreview()
                            .environmentObject(appState)
                    }

                    catalogItem(number: 4, label: "詳細画面") {
                        if let meeting = appState.meetings.first {
                            MeetingDetailView(meeting: meeting)
                                .environmentObject(appState)
                        }
                    }
                }
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.echoBgPage)
    }

    private func catalogItem<Content: View>(
        number: Int,
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.black)
                    .clipShape(Circle())

                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.96)
                    .foregroundStyle(Color.echoTextTertiary)
                    .textCase(.uppercase)
            }

            content()
        }
    }

    private var menuBarMock: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack {
                Spacer()
                MenuBarLabelView(iconController: MenuBarIconController())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.echoMenuBarBg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            MenuBarDropdownView()
                .environmentObject(appState)
                .environmentObject(PanelCoordinator())
        }
        .padding(16)
        .background(Color.echoBgPage)
        .clipShape(RoundedRectangle(cornerRadius: EchoRadius.window, style: .continuous))
    }
}

private struct HistoryListPreview: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 6) {
                    WaveformIcon()
                    Text("Echo — 履歴")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.echoTextSecondary)
                }
                HStack {
                    TrafficLights()
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .overlay(alignment: .bottom) { EchoDivider() }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.echoTextTertiary)
                Text("「\(appState.searchQuery)」を検索中 — \(appState.filteredMeetings.count)件ヒット")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.echoTextTertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.echoBgPage)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(14)
            .overlay(alignment: .bottom) { EchoDivider() }

            VStack(spacing: 2) {
                ForEach(appState.filteredMeetings) { meeting in
                    MeetingRowView(
                        meeting: meeting,
                        isSelected: meeting.id == appState.meetings.first?.id,
                        highlightTerm: appState.searchQuery
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(height: 460)
        .background(Color.echoBgPanel)
        .clipShape(RoundedRectangle(cornerRadius: EchoRadius.window, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 30, x: 0, y: 20)
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}
