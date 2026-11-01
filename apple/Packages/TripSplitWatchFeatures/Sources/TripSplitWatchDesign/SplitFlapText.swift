import SwiftUI

/// Departure-board lettering that flips in letter by letter the first time it scrolls into view.
/// Reduce Motion swaps the flips for a cross-fade.
public struct SplitFlapText: View {
  private let text: String
  @State private var elapsed: Double = 0
  @State private var shown = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(_ text: String) {
    self.text = text
  }

  private var duration: Double {
    Double(text.count) * FlapRenderer.stagger + FlapRenderer.flip
  }

  public var body: some View {
    Text(text)
      .boardFont(15, .heavy)
      .tracking(em: 0.06, size: 15)
      .foregroundStyle(WatchTheme.flapInk)
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .textRenderer(FlapRenderer(elapsed: reduceMotion ? duration : elapsed))
      .opacity(reduceMotion && !shown ? 0 : 1)
      .padding(.horizontal, 5)
      .padding(.vertical, 2)
      .background(
        LinearGradient(
          stops: [
            .init(color: WatchTheme.flapTop, location: 0.5),
            .init(color: WatchTheme.flapBottom, location: 0.5),
          ], startPoint: .top, endPoint: .bottom),
        in: .rect(cornerRadius: 4)
      )
      .onScrollVisibilityChange(threshold: 0.5) { visible in
        guard visible, !shown else { return }
        if reduceMotion {
          withAnimation(.easeInOut(duration: 0.3)) { shown = true }
        } else {
          shown = true
          withAnimation(.linear(duration: duration)) { elapsed = duration }
        }
      }
  }
}

/// Draws each glyph folding down from its midline, 40ms after the one before.
struct FlapRenderer: TextRenderer {
  static let stagger = 0.04
  static let flip = 0.16

  var elapsed: Double

  var animatableData: Double {
    get { elapsed }
    set { elapsed = newValue }
  }

  func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    var index = 0
    for line in layout {
      for run in line {
        for glyph in run {
          let progress = min(1, max(0, (elapsed - Double(index) * Self.stagger) / Self.flip))
          index += 1
          guard progress > 0 else { continue }
          let bounds = glyph.typographicBounds.rect
          var copy = context
          copy.translateBy(x: 0, y: bounds.midY)
          copy.scaleBy(x: 1, y: progress)
          copy.translateBy(x: 0, y: -bounds.midY)
          copy.draw(glyph)
        }
      }
    }
  }
}
