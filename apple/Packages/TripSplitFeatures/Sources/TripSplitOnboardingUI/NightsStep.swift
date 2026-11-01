import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain

/// Step 3: nights at each stop, which together decide the trip's length and return date.
struct NightsStep: View {
  @Environment(AppModel.self) private var model

  private var draft: OnboardingDraft { model.onboarding }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text("\(draft.days)")
            .typeface(68, .heavy, tracking: -0.04, relativeTo: .largeTitle, maximum: 1.2)
            .monospacedDigit().foregroundStyle(Theme.accentText)
            .contentTransition(.numericText(value: Double(draft.days)))
          Text(draft.days == 1 ? "day" : "days")
            .typeface(20, .heavy, relativeTo: .title3, maximum: 1.3).foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .combine)
        Text(range).typeface(15, .bold, relativeTo: .subheadline, maximum: 1.4)
          .foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
      }
      VStack(spacing: 0) {
        ForEach(Array(draft.stops.enumerated()), id: \.element.id) { index, stop in
          if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
          row(stop, at: index)
        }
      }
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
    .animation(Motion.bump, value: draft.days)
  }

  private var range: String {
    let from = CivilDate.display(draft.startsOn, format: "EEEE d MMMM")
    let to = CivilDate.display(draft.returnDate, format: "EEEE d MMMM")
    return "\(from) → \(to) · \(draft.nights) night\(draft.nights == 1 ? "" : "s")"
  }

  private func row(_ stop: Stop, at index: Int) -> some View {
    let arrives = CivilDate.adding(
      draft.stops.prefix(index).reduce(0) { $0 + $1.nights }, to: draft.startsOn)
    let leaves = CivilDate.adding(stop.nights, to: arrives)
    return HStack(spacing: 12) {
      Text(stop.flag).font(.system(size: 30)).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(stop.place).typeface(16, .heavy, relativeTo: .headline, maximum: 1.4)
          .foregroundStyle(Theme.ink).lineLimit(1)
        Text(
          arrives == leaves
            ? CivilDate.display(arrives)
            : "\(CivilDate.display(arrives)) – \(CivilDate.display(leaves))"
        )
        .typeface(12.5, .bold, relativeTo: .caption, maximum: 1.4).foregroundStyle(Theme.secondary)
      }
      Spacer(minLength: 8)
      NightsStepper(
        place: stop.place, nights: stop.nights, range: draft.nightRange
      ) { nights in
        Haptics.selection()
        withAnimation(Motion.bump) { model.onboarding.setNights(nights, at: index) }
      }
    }
    .padding(.vertical, 12).padding(.leading, 16).padding(.trailing, 12)
  }
}

/// A − count + pill. VoiceOver adjusts it by swiping up and down.
private struct NightsStepper: View {
  let place: String
  let nights: Int
  let range: ClosedRange<Int>
  let change: (Int) -> Void

  var body: some View {
    HStack(spacing: 4) {
      button("minus", enabled: nights > range.lowerBound) { change(nights - 1) }
      VStack(spacing: 0) {
        Text("\(nights)").typeface(18, .black, relativeTo: .headline, maximum: 1.3)
          .monospacedDigit().foregroundStyle(Theme.ink)
          .contentTransition(.numericText(value: Double(nights)))
        Text("NIGHTS").typeface(10.5, .heavy, tracking: 0.08, relativeTo: .caption2, maximum: 1.3)
          .foregroundStyle(Theme.secondary).lineLimit(1).fixedSize()
      }.frame(minWidth: 46)
      button("plus", enabled: nights < range.upperBound) { change(nights + 1) }
    }
    .padding(5)
    .background(Theme.inset, in: Capsule())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Nights in \(place)")
    .accessibilityValue("\(nights) night\(nights == 1 ? "" : "s")")
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment where nights < range.upperBound: change(nights + 1)
      case .decrement where nights > range.lowerBound: change(nights - 1)
      default: break
      }
    }
    .accessibilityIdentifier("onboarding.nights.\(place)")
  }

  private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View
  {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 14, weight: .heavy))
        .foregroundStyle(enabled ? Theme.ink : Theme.tertiary)
        .frame(width: 34, height: 34).background(Theme.surface, in: Circle())
        .contentShape(Circle())
    }.buttonStyle(PressStyle(scale: 0.88)).disabled(!enabled)
  }
}
