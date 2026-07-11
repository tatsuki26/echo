import SwiftUI

struct HistoryWindowView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            content
                .frame(minWidth: 640, minHeight: 560)
                .background(Color.echoBgPage)
                .toolbar { toolbarContent }
                .toolbarBackground(Color.echoBgPanel, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch appState.mainWindowScreen {
        case .home:
            HomeView()
        case .history:
            historyList
        case .detail:
            if let meeting = appState.selectedMeeting {
                MeetingDetailView(meeting: meeting)
            } else {
                HomeView()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if appState.mainWindowScreen == .detail {
            ToolbarItem(placement: .navigation) {
                Button {
                    appState.mainWindowScreen = .history
                } label: {
                    Label("履歴", systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
            }

            ToolbarItem(placement: .principal) {
                Text(appState.selectedMeeting?.title ?? "会議詳細")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.echoTextPrimary)
                    .lineLimit(1)
            }

            if let meeting = appState.selectedMeeting {
                ToolbarItem(placement: .destructiveAction) {
                    Button("削除", role: .destructive) {
                        appState.deleteMeeting(id: meeting.id)
                    }
                }
            }
        } else {
            ToolbarItem(placement: .principal) {
                Picker("画面", selection: homeHistorySelection) {
                    Text("ホーム").tag(MainWindowScreen.home)
                    Text("履歴").tag(MainWindowScreen.history)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 156)
            }
        }
    }

    private var homeHistorySelection: Binding<MainWindowScreen> {
        Binding(
            get: {
                appState.mainWindowScreen == .history ? .history : .home
            },
            set: { appState.mainWindowScreen = $0 }
        )
    }

    private var historyList: some View {
        VStack(spacing: 0) {
            searchBar
            meetingList
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Color.echoTextTertiary)

            ZStack(alignment: .leading) {
                if appState.searchQuery.isEmpty {
                    Text("会議を検索")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.echoTextTertiary)
                }

                TextField("", text: $appState.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(
                        appState.searchQuery.isEmpty ? Color.clear : Color.echoTextPrimary
                    )
            }

            if !appState.searchQuery.isEmpty {
                Text("\(appState.filteredMeetings.count)件")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.echoTextTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.echoBgPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.echoBorder, lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.echoBgPage)
        .overlay(alignment: .bottom) { EchoDivider() }
    }

    private var meetingList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(appState.filteredMeetings) { meeting in
                    MeetingRowView(
                        meeting: meeting,
                        isSelected: appState.selectedMeetingID == meeting.id,
                        highlightTerm: appState.searchQuery
                    )
                    .onTapGesture {
                        appState.selectedMeetingID = meeting.id
                        appState.mainWindowScreen = .detail
                    }
                    .contextMenu {
                        Button("削除", role: .destructive) {
                            appState.deleteMeeting(id: meeting.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
