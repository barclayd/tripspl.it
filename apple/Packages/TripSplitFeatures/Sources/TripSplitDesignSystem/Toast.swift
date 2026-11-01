import SwiftUI

/// A confirmation pill: an ink capsule with a green tick, e.g. "£42.10 added to Day 3".
package struct Toast: View {
  package init(_ text: String) { self.text = text }
  var text: String

  package var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "checkmark")
        .font(.system(size: 11, weight: .black))
        .foregroundStyle(Theme.goodInk)
        .frame(width: 22, height: 22)
        .background(Theme.good, in: Circle())
        .accessibilityHidden(true)
      Text(text)
        .typeface(14, .heavy, relativeTo: .subheadline, maximum: 1.4)
        .foregroundStyle(Theme.background)
        .lineLimit(2)
    }
    .padding(.vertical, 10).padding(.leading, 10).padding(.trailing, 16)
    .background(Theme.ink, in: Capsule())
    .shadow(color: .black.opacity(0.25), radius: 15, y: 12)
  }
}

extension View {
  /// Drops `text` in from the top with a small overshoot, and reads it out to VoiceOver.
  public func toast(_ text: String?) -> some View {
    overlay(alignment: .top) {
      ZStack {
        if let text {
          Toast(text)
            .id(text)
            .padding(.top, 6)
            .padding(.horizontal, 20)
            .transition(.offset(y: -90).combined(with: .opacity))
        }
      }
      .animation(.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.55), value: text)
      .allowsHitTesting(false)
    }
    .onChange(of: text) { _, text in
      if let text { AccessibilityNotification.Announcement(text).post() }
    }
  }
}
