import SwiftUI

extension Color {
    static let echoBgPage = Color(red: 0.929, green: 0.929, blue: 0.941)
    static let echoBgPanel = Color.white
    static let echoBgPanelTranslucent = Color.white.opacity(0.72)
    static let echoTextPrimary = Color(red: 0.114, green: 0.114, blue: 0.122)
    static let echoTextSecondary = Color(red: 0.431, green: 0.431, blue: 0.451)
    static let echoTextTertiary = Color(red: 0.631, green: 0.631, blue: 0.651)
    static let echoBorder = Color.black.opacity(0.08)
    static let echoAccent = Color(red: 0.176, green: 0.357, blue: 1.0)
    static let echoAccentTeal = Color(red: 0.0, green: 0.761, blue: 0.659)
    static let echoSpeakerA = Color(red: 0.176, green: 0.357, blue: 1.0)
    static let echoSpeakerB = Color(red: 1.0, green: 0.478, blue: 0.271)
    static let echoDanger = Color(red: 1.0, green: 0.231, blue: 0.188)
    static let echoMenuBarBg = Color(red: 0.122, green: 0.122, blue: 0.133)
    static let echoHighlight = Color(red: 1.0, green: 0.839, blue: 0.039).opacity(0.4)
}

enum EchoRadius {
    static let window: CGFloat = 12
    static let card: CGFloat = 10
}

enum EchoShadow {
    static let window = Color.black.opacity(0.18)
}

struct EchoDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.echoBorder)
            .frame(height: 1)
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct TranslucentPanelBackground: View {
    var cornerRadius: CGFloat = EchoRadius.window

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
            Color.echoBgPanelTranslucent
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
