import SwiftUI

/// Lays subviews out left to right, wrapping onto new lines like words in a paragraph.
package struct FlowLayout: Layout {
  package init(spacing: CGFloat = 8, lineSpacing: CGFloat? = nil) {
    self.spacing = spacing
    self.lineSpacing = lineSpacing ?? spacing
  }

  package var spacing: CGFloat
  package var lineSpacing: CGFloat

  package func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize
  {
    let lines = arrange(subviews, width: proposal.width ?? .infinity)
    let width = lines.map(\.width).max() ?? 0
    let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
    return CGSize(width: proposal.width ?? width, height: height)
  }

  package func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var y = bounds.minY
    for line in arrange(subviews, width: bounds.width) {
      var x = bounds.minX
      for (index, size) in zip(line.indices, line.sizes) {
        subviews[index].place(
          at: CGPoint(x: x, y: y + (line.height - size.height) / 2), anchor: .topLeading,
          proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += line.height + lineSpacing
    }
  }

  private struct Line {
    var indices: [Int] = []
    var sizes: [CGSize] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func arrange(_ subviews: Subviews, width: CGFloat) -> [Line] {
    var lines: [Line] = []
    var line = Line()
    for (index, subview) in subviews.enumerated() {
      let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
      let needed = line.indices.isEmpty ? size.width : line.width + spacing + size.width
      if needed > width, !line.indices.isEmpty {
        lines.append(line)
        line = Line()
      }
      line.width = line.indices.isEmpty ? size.width : line.width + spacing + size.width
      line.height = max(line.height, size.height)
      line.indices.append(index)
      line.sizes.append(CGSize(width: min(size.width, width), height: size.height))
    }
    if !line.indices.isEmpty { lines.append(line) }
    return lines
  }
}
