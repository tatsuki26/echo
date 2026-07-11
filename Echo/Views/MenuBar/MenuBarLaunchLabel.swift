import SwiftUI

struct MenuBarLaunchLabel: View {
    @EnvironmentObject private var iconController: MenuBarIconController

    var body: some View {
        MenuBarLabelView(iconController: iconController)
    }
}
