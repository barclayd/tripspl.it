import SwiftUI

/// TripSplit's signature ring: a dashed arc drawn on a 50-unit circle, so every gauge reads as
/// segments rather than a smooth sweep. Closed rings start at 12 o'clock; open rings leave their
/// gap at the bottom (135° → 405°) for a flag or label.
public struct SegmentedArc: Shape {
  public enum Layout: Sendable {
    case closed, open
  }

  var layout: Layout
  var count: Int
  var segments: Range<Int>
  var radius: CGFloat
  var lineWidth: CGFloat
  var gap: CGFloat

  public init(
    _ layout: Layout, count: Int, segments: Range<Int>? = nil, radius: CGFloat? = nil,
    lineWidth: CGFloat = 3.5, gap: CGFloat = 3
  ) {
    self.layout = layout
    self.count = max(count, 1)
    self.segments = segments ?? 0..<max(count, 1)
    self.radius = radius ?? (layout == .closed ? 21 : 20)
    self.lineWidth = lineWidth
    self.gap = gap
  }

  /// The first `filled` of `count` segments, with `fraction` rounded to whole segments.
  public static func filled(_ fraction: Double, of count: Int) -> Int {
    min(max(Int((fraction * Double(count)).rounded()), 0), count)
  }

  public func path(in rect: CGRect) -> Path {
    let scale = min(rect.width, rect.height) / 50
    let centre = CGPoint(x: rect.midX, y: rect.midY)
    let (start, span): (Double, Double) = layout == .closed ? (-90, 360) : (135, 270)
    let length = Double(radius) * span * .pi / 180
    let gaps = Double(layout == .closed ? count : count - 1)
    // Long trips get more segments than the arc can space at 3 units, so the gap shrinks.
    let gap = min(Double(gap), length / Double(count) / 3)
    let segment = (length - gaps * gap) / Double(count)
    let step = (segment + gap) / Double(radius)
    let sweep = segment / Double(radius)
    var path = Path()
    for index in segments.clamped(to: 0..<count) {
      let from = start * .pi / 180 + Double(index) * step
      // Each segment is its own subpath, or the stroke bridges the gaps between them.
      path.move(
        to: CGPoint(
          x: centre.x + radius * scale * cos(from), y: centre.y + radius * scale * sin(from)))
      path.addArc(
        center: centre, radius: radius * scale, startAngle: .radians(from),
        endAngle: .radians(from + sweep), clockwise: false)
    }
    return path.strokedPath(.init(lineWidth: lineWidth * scale, lineCap: .butt))
  }
}
