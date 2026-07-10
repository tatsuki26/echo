import SwiftUI

struct RecordingDot: View {
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(Color.echoDanger)
            .frame(width: size, height: size)
            .shadow(color: Color.echoDanger.opacity(0.15), radius: 0, x: 0, y: 0)
            .overlay {
                Circle()
                    .stroke(Color.echoDanger.opacity(0.15), lineWidth: 3)
                    .frame(width: size + 6, height: size + 6)
            }
    }
}
