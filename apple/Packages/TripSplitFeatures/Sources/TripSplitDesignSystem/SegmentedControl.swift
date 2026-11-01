import SwiftUI

/// The design's segmented control: an inset track with a surface thumb that springs between
/// options.
package struct SegmentedControl<Value: Hashable>: View {
  package init(
    _ label: String, selection: Binding<Value>, options: [(value: Value, title: String)]
  ) {
    self.label = label
    _selection = selection
    self.options = options
  }
  private let label: String
  @Binding private var selection: Value
  private let options: [(value: Value, title: String)]
  @Namespace private var thumb
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  package var body: some View {
    HStack(spacing: 0) {
      ForEach(options.indices, id: \.self) { index in
        let option = options[index]
        let selected = option.value == selection
        Button {
          withAnimation(reduceMotion ? nil : .timingCurve(0.34, 1.3, 0.64, 1, duration: 0.4)) {
            selection = option.value
          }
        } label: {
          Text(option.title)
            .typeface(14, .heavy, relativeTo: .subheadline, maximum: 1.3)
            .foregroundStyle(selected ? Theme.ink : Theme.secondary)
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(9)
            .frame(maxWidth: .infinity)
            .background {
              if selected {
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.surface)
                  .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                  .matchedGeometryEffect(id: "thumb", in: thumb)
              }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: selected) { _, now in now }
      }
    }
    .padding(3)
    .background(
      Theme.inset, in: RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel(label)
  }
}
