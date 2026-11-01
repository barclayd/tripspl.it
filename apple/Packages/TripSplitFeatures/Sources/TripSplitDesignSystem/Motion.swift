import SwiftUI

/// Timing curves from the design's keyframes.
package enum Motion {
  /// Screen push, 480ms.
  package static let push = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.48)
  /// Sheet rising with a slight overshoot, 550ms.
  package static let sheet = Animation.timingCurve(0.2, 1.12, 0.3, 1, duration: 0.55)
  /// Pop in with overshoot, 500ms.
  package static let popIn = Animation.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.5)
  /// Value bump, 340ms.
  package static let bump = Animation.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.34)
  /// Content rising into place, 550ms.
  package static let rise = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.55)
  /// Card spring, 500ms.
  package static let spring = Animation.timingCurve(0.34, 1.25, 0.64, 1, duration: 0.5)
  /// A card tucking to the back of a stack, 550ms.
  package static let tuck = Animation.timingCurve(0.22, 1.2, 0.36, 1, duration: 0.55)
  /// Count-up tween: ease-out quart over 1s.
  package static let countUp = Animation.timingCurve(0.25, 1, 0.5, 1, duration: 1)
  /// Receipt printing out of the slot, 1250ms.
  package static let receipt = Animation.timingCurve(0.3, 0.75, 0.3, 1, duration: 1.25)
}

private struct Rise: ViewModifier {
  let delay: Double
  let distance: CGFloat
  @State private var shown = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content.opacity(shown || reduceMotion ? 1 : 0)
      .offset(y: shown || reduceMotion ? 0 : distance)
      .onAppear {
        guard !shown else { return }
        withAnimation(Motion.rise.delay(delay)) { shown = true }
      }
  }
}

private struct PopIn: ViewModifier {
  let delay: Double
  @State private var shown = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content.scaleEffect(shown || reduceMotion ? 1 : 0.3)
      .opacity(shown || reduceMotion ? 1 : 0)
      .onAppear {
        guard !shown else { return }
        withAnimation(Motion.popIn.delay(delay)) { shown = true }
      }
  }
}

private struct ScaleKeyframes<Trigger: Equatable>: ViewModifier {
  let trigger: Trigger
  let values: [CGFloat]
  let duration: Double
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    if reduceMotion {
      content
    } else {
      content.keyframeAnimator(initialValue: CGFloat(1), trigger: trigger) { view, scale in
        view.scaleEffect(scale)
      } keyframes: { _ in
        KeyframeTrack {
          for value in values {
            CubicKeyframe(value, duration: duration / Double(values.count))
          }
        }
      }
    }
  }
}

private struct Shake<Trigger: Equatable>: ViewModifier {
  let trigger: Trigger
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    if reduceMotion {
      content
    } else {
      content.keyframeAnimator(initialValue: CGFloat(0), trigger: trigger) { view, x in
        view.offset(x: x)
      } keyframes: { _ in
        KeyframeTrack {
          for x: CGFloat in [-8, 8, -5, 5, 0] { LinearKeyframe(x, duration: 0.07) }
        }
      }
    }
  }
}

extension View {
  /// Fades in while rising 18pt.
  package func rise(delay: Double = 0, distance: CGFloat = 18) -> some View {
    modifier(Rise(delay: delay, distance: distance))
  }
  /// Scales in from 0.3 with overshoot.
  package func popIn(delay: Double = 0) -> some View {
    modifier(PopIn(delay: delay))
  }
  /// Scales 1 → 1.14 → 1 whenever `trigger` changes.
  package func bump<T: Equatable>(on trigger: T) -> some View {
    modifier(ScaleKeyframes(trigger: trigger, values: [1.14, 1], duration: 0.34))
  }
  /// Squeezes then springs a tick: 1 → 0.78 → 1.18 → 1.
  package func tick<T: Equatable>(on trigger: T) -> some View {
    modifier(ScaleKeyframes(trigger: trigger, values: [0.78, 1.18, 1], duration: 0.5))
  }
  /// Horizontal shake for rejected input.
  package func shake<T: Equatable>(on trigger: T) -> some View {
    modifier(Shake(trigger: trigger))
  }
}

/// An ink stamp that slams onto the page: 2.6× at -4° to 1× at -12°.
package struct Stamp<Content: View>: View {
  package init(rotation: Double = -12, delay: Double = 0, @ViewBuilder content: () -> Content) {
    self.rotation = rotation
    self.delay = delay
    self.content = content()
  }
  package var rotation: Double
  package var delay: Double
  private let content: Content
  @State private var landed = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  package var body: some View {
    content.rotationEffect(.degrees(rotation))
      .opacity(landed || reduceMotion ? 1 : 0)
      .keyframeAnimator(initialValue: StampFrame(), trigger: landed) { view, frame in
        view.scaleEffect(frame.scale).rotationEffect(.degrees(frame.turn))
      } keyframes: { _ in
        KeyframeTrack(\.scale) {
          LinearKeyframe(2.6, duration: 0.01)
          CubicKeyframe(0.92, duration: 0.42)
          CubicKeyframe(1, duration: 0.27)
        }
        KeyframeTrack(\.turn) {
          LinearKeyframe(8, duration: 0.01)
          CubicKeyframe(-2, duration: 0.42)
          CubicKeyframe(0, duration: 0.27)
        }
      }
      .task {
        guard !landed, !reduceMotion else { return }
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        landed = true
      }
  }
}

/// Offsets from a stamp's resting scale and rotation.
private struct StampFrame {
  var scale: CGFloat = 1
  var turn: Double = 0
}
