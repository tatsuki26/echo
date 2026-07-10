import SwiftUI

struct HistoryWindowView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.isShowingDetail, let meeting = appState.selectedMeeting {
                MeetingDetailView(meeting: meeting)
            } else {
                historyList
            }
        }
        .frame(minWidth: 420, minHeight: 460)
        .background(Color.echoBgPanel)
    }

    private var historyList: some View {
        VStack(spacing: 0) {
            titleBar
            searchBar
            meetingList
        }
        .background(Color.echoBgPanel)
        .clipShape(RoundedRectangle(cornerRadius: EchoRadius.window, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 30, x: 0, y: 20)
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }

    private var titleBar: some View {
        ZStack {
            HStack(spacing: 6) {
                WaveformIcon(animated: true, targetFPS: 60)
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
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
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
                Text("「\(appState.searchQuery)」を検索中 — \(appState.filteredMeetings.count)件ヒット")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.echoTextTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.echoBgPage)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(14)
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
                        appState.isShowingDetail = true
                    }
                    .contextMenu {
                        Button("削除", role: .destructive) {
                            appState.deleteMeeting(id: meeting.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }
}
