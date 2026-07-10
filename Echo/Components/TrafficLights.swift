import SwiftUI

struct TrafficLights: View {
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Color(red: 1.0, green: 0.373, blue: 0.341)).frame(width: 11, height: 11)
            Circle().fill(Color(red: 0.996, green: 0.737, blue: 0.180)).frame(width: 11, height: 11)
            Circle().fill(Color(red: 0.157, green: 0.784, blue: 0.251)).frame(width: 11, height: 11)
        }
    }
}
