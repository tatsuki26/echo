import SwiftUI

/// メニューバーアイコン（起動時にウィンドウを自動で開かない）
struct MenuBarLaunchLabel: View {
    @EnvironmentObject private var iconController: MenuBarIconController

    var body: some View {
        MenuBarLabelView(iconController: iconController)
    }
}
