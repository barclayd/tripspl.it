import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain

/// Step 3, for a route with more than one stop: how the dates you picked split between places.
/// Adding a night somewhere takes it from a neighbour, so the trip keeps its length.
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
        place: stop.place, nights: stop.nights,
        canDecrease: draft.canShiftNight(at: index, by: -1),
        canIncrease: draft.canShiftNight(at: index, by: 1)
      ) { delta in
        Haptics.selection()
        withAnimation(Motion.bump) { model.onboarding.shiftNight(at: index, by: delta) }
      }
    }
    .padding(.vertical, 12).padding(.leading, 16).padding(.trailing, 12)
  }
}

/// A − count + pill. VoiceOver adjusts it by swiping up and down.
private struct NightsStepper: View {
  let place: String
  let nights: Int
  let canDecrease: Bool
  let canIncrease: Bool
  let change: (Int) -> Void

  var body: some View {
    HStack(spacing: 4) {
      button("minus", enabled: canDecrease) { change(-1) }
      VStack(spacing: 0) {
        Text("\(nights)").typeface(18, .black, relativeTo: .headline, maximum: 1.3)
          .monospacedDigit().foregroundStyle(Theme.ink)
          .contentTransition(.numericText(value: Double(nights)))
        Text("NIGHTS").typeface(10.5, .heavy, tracking: 0.08, relativeTo: .caption2, maximum: 1.3)
          .foregroundStyle(Theme.secondary).lineLimit(1).fixedSize()
      }.frame(minWidth: 46)
      button("plus", enabled: canIncrease) { change(1) }
    }
    .padding(5)
    .background(Theme.inset, in: Capsule())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Nights in \(place)")
    .accessibilityValue("\(nights) night\(nights == 1 ? "" : "s")")
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment where canIncrease: change(1)
      case .decrement where canDecrease: change(-1)
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
