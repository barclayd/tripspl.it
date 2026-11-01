import SwiftUI

/// A Solari split-flap readout.
///
/// Each cell steps one character round the drum per 64ms tick, with a left-to-right cascade.
/// A flip drops the old character's top leaf, then lands the new character's bottom leaf.
/// The animation is a pure function of elapsed time, so it is redrawn from a timeline and
/// pauses once every cell has settled.
package struct FlapText: View {
  package init(
    _ value: String, count: Int? = nil, alignment: HorizontalAlignment = .leading,
    delay: Double = 0, cellWidth: CGFloat = 11, cellHeight: CGFloat = 18,
    fontSize: CGFloat = 12.5, color: Color = Theme.flapInk
  ) {
    self.value = value
    self.count = count ?? value.count
    self.alignment = alignment
    self.delay = delay
    self.cellWidth = cellWidth
    self.cellHeight = cellHeight
    self.fontSize = fontSize
    self.color = color
  }

  /// Sizes the cells from a font size, as the board readouts do.
  package init(value: String, count: Int, size: CGFloat = 12.5, color: Color = Theme.flapInk) {
    self.init(
      value, count: count, cellWidth: (size * 0.88).rounded(), cellHeight: (size * 1.44).rounded(),
      fontSize: size, color: color)
  }

  package var value: String
  package var count: Int
  package var alignment: HorizontalAlignment
  package var delay: Double
  package var cellWidth: CGFloat
  package var cellHeight: CGFloat
  package var fontSize: CGFloat
  package var color: Color

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var run: FlapRun?
  @State private var animating = false

  private var target: [Character] { FlapRun.pad(value, to: count, trailing: alignment == .trailing) }

  package var body: some View {
    let target = target
    TimelineView(.animation(paused: !animating)) { context in
      let frames = (run ?? FlapRun(from: target, to: target, start: .distantPast)).frames(
        at: context.date)
      HStack(spacing: 1) {
        ForEach(frames.indices, id: \.self) { index in
          FlapCell(
            frame: frames[index], width: cellWidth, height: cellHeight, fontSize: fontSize,
            color: color)
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(value)
    .onChange(of: target, initial: true) { _, newTarget in
      if reduceMotion {
        run = FlapRun(from: newTarget, to: newTarget, start: .distantPast)
        return
      }
      let now = Date()
      let shown =
        run?.frames(at: now).map(\.current)
        ?? Array(repeating: " ", count: newTarget.count)
      let from = FlapRun.pad(String(shown), to: newTarget.count, trailing: false)
      run = FlapRun(from: from, to: newTarget, start: now.addingTimeInterval(delay))
    }
    .task(id: run) {
      guard let run, run.settles > .now else {
        animating = false
        return
      }
      animating = true
      try? await Task.sleep(for: .seconds(run.settles.timeIntervalSinceNow))
      guard !Task.isCancelled else { return }
      animating = false
    }
  }
}

/// One deterministic flap sequence from `from` to `to`.
private struct FlapRun: Equatable {
  static let drum = Array(" ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-./:")
  static let tick = 0.064
  static let safety = 6.0

  let start: Date
  let sequences: [[Character]]
  let target: [Character]

  init(from: [Character], to: [Character], start: Date) {
    self.start = start
    self.target = to
    self.sequences = zip(from, to).map { Self.sequence(from: $0, to: $1) }
  }

  static func pad(_ value: String, to count: Int, trailing: Bool) -> [Character] {
    let upper = Array(value.uppercased())
    if upper.count >= count {
      return trailing ? Array(upper.suffix(count)) : Array(upper.prefix(count))
    }
    let padding = Array(repeating: Character(" "), count: count - upper.count)
    return trailing ? padding + upper : upper + padding
  }

  /// Characters a cell shows on its way to `target`, including both ends.
  static func sequence(from start: Character, to target: Character) -> [Character] {
    guard start != target else { return [start] }
    guard drum.contains(target) else { return [start, target] }
    var chars = [start]
    var current = start
    while current != target, chars.count <= drum.count + 1 {
      if let index = drum.firstIndex(of: current) {
        current = drum[(index + 1) % drum.count]
      } else {
        current = " "
      }
      chars.append(current)
    }
    return chars
  }

  /// When every cell has landed, capped at the safety snap.
  var settles: Date {
    let longest = sequences.indices.map { $0 + sequences[$0].count }.max() ?? 0
    return start.addingTimeInterval(min(Self.safety, Double(longest + 1) * Self.tick))
  }

  func frames(at date: Date) -> [FlapFrame] {
    let elapsed = date.timeIntervalSince(start)
    guard elapsed < Self.safety else { return target.map { FlapFrame(current: $0) } }
    let ticks = max(0, elapsed / Self.tick - 1)
    return sequences.indices.map { index in
      let sequence = sequences[index]
      let local = ticks - Double(index)
      guard local > 0 else { return FlapFrame(current: sequence[0]) }
      let step = Int(local)
      guard step < sequence.count - 1 else { return FlapFrame(current: sequence[sequence.count - 1]) }
      return FlapFrame(
        current: sequence[step], next: sequence[step + 1], progress: local - Double(step))
    }
  }
}

private struct FlapFrame {
  var current: Character
  var next: Character?
  var progress: Double = 0
}

private struct FlapCell: View {
  let frame: FlapFrame
  let width: CGFloat
  let height: CGFloat
  let fontSize: CGFloat
  let color: Color

  var body: some View {
    let radius = max(2, width * 0.14)
    ZStack(alignment: .top) {
      VStack(spacing: 0) {
        half(frame.next ?? frame.current, top: true, radius: radius)
        half(frame.current, top: false, radius: radius)
      }
      if let next = frame.next {
        if frame.progress < 0.5 {
          let k = Self.easeIn(frame.progress * 2)
          half(frame.current, top: true, radius: radius)
            .overlay(alignment: .bottom) {
              LinearGradient(
                colors: [.clear, .black.opacity(0.5 * k + 0.2)], startPoint: .top,
                endPoint: .bottom
              ).frame(height: 6)
            }
            .rotation3DEffect(
              .degrees(-90 * k), axis: (1, 0, 0), anchor: .bottom, perspective: 0.4)
        } else {
          let k = Self.easeOut((frame.progress - 0.5) * 2)
          half(next, top: false, radius: radius)
            .rotation3DEffect(
              .degrees(90 * (1 - k)), axis: (1, 0, 0), anchor: .top, perspective: 0.4)
            .offset(y: height / 2)
        }
      }
      Rectangle().fill(.black.opacity(0.7)).frame(height: 1).offset(y: height / 2 - 0.5)
    }
    .frame(width: width, height: height, alignment: .top)
  }

  private func half(_ char: Character, top: Bool, radius: CGFloat) -> some View {
    Text(String(char))
      .font(.system(size: fontSize, weight: .bold, design: .monospaced))
      .foregroundStyle(color)
      .frame(width: width, height: height)
      .frame(width: width, height: height / 2, alignment: top ? .top : .bottom)
      .clipped()
      .background(top ? Theme.flapTop : Theme.flapBottom)
      .clipShape(
        UnevenRoundedRectangle(
          topLeadingRadius: top ? radius : 0, bottomLeadingRadius: top ? 0 : radius,
          bottomTrailingRadius: top ? 0 : radius, topTrailingRadius: top ? radius : 0))
  }

  /// cubic-bezier(.55, 0, 1, .45), approximated.
  private static func easeIn(_ t: Double) -> Double { pow(min(max(t, 0), 1), 2.2) }
  /// cubic-bezier(0, .55, .45, 1), approximated.
  private static func easeOut(_ t: Double) -> Double { 1 - pow(1 - min(max(t, 0), 1), 2.2) }
}
