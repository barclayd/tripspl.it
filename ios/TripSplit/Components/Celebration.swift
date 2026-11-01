import SwiftUI

struct Celebration: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var began = Date()
  @State private var active = true
  private let colors: [Color] = [
    Theme.accent, Color(hex: 0xFFC93C), Color(hex: 0x3BCEAC), Color(hex: 0x5B8CFF),
    Color(hex: 0xFF7A59),
  ]
  var body: some View {
    if !reduceMotion {
      TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { timeline in
        Canvas { context, size in
          let elapsed = timeline.date.timeIntervalSince(began)
          for index in 0..<42 {
            let delay = Double(index % 7) * 0.045
            let progress = max(0, (elapsed - delay) / (1.8 + Double(index % 5) * 0.18))
            guard progress > 0, progress < 1 else { continue }
            let origin = Double((index * 73) % 100) / 100
            let x = size.width * origin + sin(progress * 6 + Double(index)) * 28
            let y = -20 + progress * (size.height + 80)
            var particle = context
            particle.opacity = min(1, (1 - progress) * 4)
            particle.translateBy(x: x, y: y)
            particle.rotate(by: .degrees(progress * Double(index % 2 == 0 ? 520 : -420)))
            particle.fill(
              Path(roundedRect: CGRect(x: -3, y: -6, width: 6, height: 12), cornerRadius: 2),
              with: .color(colors[index % colors.count]))
          }
        }
      }.task {
        began = Date()
        try? await Task.sleep(for: .seconds(3))
        active = false
      }
      .allowsHitTesting(false).accessibilityHidden(true)
    }
  }
}
