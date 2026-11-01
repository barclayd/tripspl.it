import SwiftUI
import TripSplitDomain

/// Confetti for a finished trip: 54 pieces from a fixed seed, every seventh one a stop's flag.
package struct Celebration: View {
  package init(flags: [String] = []) {
    self.flags = flags
  }
  package var flags: [String]

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var began = Date()
  @State private var active = true

  private static let colours: [Color] = [
    Theme.accent, Color(hex: 0xFFC93C), Color(hex: 0x3BCEAC), Color(hex: 0x5B8CFF),
    Color(hex: 0xFF7A59),
  ]

  package var body: some View {
    if !reduceMotion {
      let pieces = Piece.make(flags: flags)
      TimelineView(.animation(paused: !active)) { timeline in
        Canvas { context, size in
          let elapsed = timeline.date.timeIntervalSince(began)
          let scale = size.width / 402
          for (index, piece) in pieces.enumerated() {
            let t = (elapsed - piece.delay) / piece.duration
            guard t >= 0, t <= 1 else { continue }
            let k = Self.ease(t)
            var particle = context
            particle.translateBy(x: piece.x * scale + piece.dx * k, y: -40 + 980 * k)
            particle.rotate(by: .degrees(piece.rotation * k))
            if let flag = piece.flag {
              particle.draw(Text(flag).font(.system(size: 26)), at: .zero, anchor: .topLeading)
            } else {
              let rect = CGRect(x: 0, y: 0, width: piece.width, height: piece.height)
              let path =
                piece.round
                ? Path(roundedRect: rect, cornerRadius: min(piece.width, piece.height) / 2)
                : Path(roundedRect: rect, cornerRadius: 2)
              particle.fill(path, with: .color(Self.colours[index % Self.colours.count]))
            }
          }
        }
      }
      .task {
        began = Date()
        try? await Task.sleep(for: .seconds(3.7))
        active = false
      }
      .allowsHitTesting(false).accessibilityHidden(true)
    }
  }

  /// cubic-bezier(.25, .6, .45, 1), solved for x.
  private static func ease(_ x: Double) -> Double {
    UnitCurve.bezier(
      startControlPoint: UnitPoint(x: 0.25, y: 0.6), endControlPoint: UnitPoint(x: 0.45, y: 1)
    ).value(at: x)
  }

  private struct Piece {
    var x: Double
    var dx: Double
    var rotation: Double
    var delay: Double
    var duration: Double
    var width: Double = 0
    var height: Double = 0
    var round = false
    var flag: String?

    /// Draws in the same order as the design so every launch throws the same pattern.
    static func make(flags: [String]) -> [Piece] {
      var random = Mulberry32(seed: 42)
      return (0..<54).map { index in
        let isFlag = !flags.isEmpty && index % 7 == 0
        var piece = Piece(
          x: random.next() * 402, dx: (random.next() - 0.5) * 180,
          rotation: random.next() * 900 - 450, delay: random.next() * 0.5,
          duration: 1.8 + random.next() * 1.3)
        if isFlag {
          piece.flag = flags[index % flags.count]
        } else {
          piece.width = 7 + random.next() * 6
          piece.height = 11 + random.next() * 8
        }
        piece.round = random.next() <= 0.5
        return piece
      }
    }
  }
}

/// The design's seeded generator, so confetti lands the same way every time.
private struct Mulberry32 {
  var state: UInt32
  init(seed: UInt32) { state = seed }
  mutating func next() -> Double {
    state = state &+ 0x6D2B_79F5
    var t = (state ^ (state >> 15)) &* (1 | state)
    t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
    return Double(t ^ (t >> 14)) / 4_294_967_296
  }
}
