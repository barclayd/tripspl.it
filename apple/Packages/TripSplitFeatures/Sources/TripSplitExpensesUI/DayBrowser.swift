import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitPersistence
import TripSplitSharedUI

/// The portrait calendar and native, finger-following pages share the app's day selection.
public struct DayBrowser: View {
  public init(tripID: String, attachment: Attachment, portrait: Bool, showsPaneControls: Bool) {
    self.tripID = tripID
    self.attachment = attachment
    self.portrait = portrait
    self.showsPaneControls = showsPaneControls
  }
  var tripID: String
  var attachment: Attachment
  var portrait: Bool
  var showsPaneControls: Bool
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var editingDay: TripDay?
  @State private var carouselID: String?
  @State private var browsingDates = false
  @State private var carouselWidth: CGFloat = 0
  @ScaledMetric(relativeTo: .caption) private var dayWidth = 84.0
  @Namespace private var selection

  public var body: some View {
    if let trip = model.store.trip(tripID) {
      Group {
        if portrait, attachment.kind == .day,
          let day = trip.days.first(where: { $0.id == attachment.id }) {
          VStack(spacing: 0) {
            identity(trip, day: day)
            carousel(trip)
            TabView(selection: daySelection(trip)) {
              ForEach(trip.days) { page in
                DayView(tripID: tripID, attachment: .init(kind: .day, id: page.id), showsHeader: false)
                  .tag(page.id)
              }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .accessibilityIdentifier("day.pages")
          }
          .background(Theme.background)
        } else {
          DayView(tripID: tripID, attachment: attachment, showsPaneControls: showsPaneControls)
            .id(attachment).transition(.opacity)
            .animation(.easeOut(duration: 0.2), value: attachment)
        }
      }
      .sheet(item: $editingDay) { DayLocationSheet(trip: trip, day: $0) }
    }
  }

  private func identity(_ trip: TripSnapshot, day: TripDay) -> some View {
    let location = trip.location(for: day)
    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 10) {
        Text(location?.countryCode.flag ?? trip.uniqueFlags.first ?? "🌍")
          .font(.system(size: 28)).accessibilityHidden(true)
          .contentTransition(.opacity)
        Text(trip.name)
          .typeface(25, .heavy, tracking: -0.035, relativeTo: .title2, maximum: 1.4)
          .foregroundStyle(Theme.ink).lineLimit(2)
          .accessibilityAddTraits(.isHeader)
      }
      Button { editingDay = day } label: {
        HStack(spacing: 6) {
          Image(systemName: "mappin.and.ellipse").font(.system(size: 12, weight: .semibold))
          Text(location?.place ?? "Location")
            .typeface(15, .semibold, relativeTo: .subheadline)
            .contentTransition(.opacity).lineLimit(1)
          if trip.role == "owner" {
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
          }
        }
        .foregroundStyle(Theme.secondary).padding(.vertical, 5)
        .frame(minHeight: 34, alignment: .leading).contentShape(Rectangle())
      }
      .buttonStyle(PressStyle(scale: 0.98)).disabled(trip.role != "owner")
      .accessibilityLabel("\(location?.place ?? "Location"), \(CivilDate.display(day.date, format: "EEEE d MMMM"))")
      .accessibilityHint(trip.role == "owner" ? "Change the location for this day" : "")
      .accessibilityIdentifier("day.location")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, Theme.Spacing.screen).padding(.top, 6).padding(.bottom, 8)
    .contentShape(Rectangle())
    .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
      guard abs(value.translation.width) > abs(value.translation.height) * 1.5,
        abs(value.predictedEndTranslation.width) > 60 else { return }
      move(value.translation.width < 0 ? 1 : -1, in: trip)
    })
    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: location)
  }

  private func carousel(_ trip: TripSnapshot) -> some View {
    ScrollView(.horizontal) {
      LazyHStack(spacing: 6) {
        ForEach(Array(trip.days.enumerated()), id: \.element.id) { index, day in
          let selected = day.id == attachment.id
          Button { select(day.id, in: trip) } label: {
            VStack(spacing: 4) {
              Text(relativeLabel(day, trip: trip))
                .typeface(11.5, .bold, relativeTo: .caption, maximum: 1.4).lineLimit(1)
              Text(CivilDate.display(day.date, format: "d MMM"))
                .typeface(20, .heavy, tracking: -0.025, relativeTo: .title3, maximum: 1.4)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.85)
              Text("Day \(index + 1)")
                .typeface(10.5, .semibold, relativeTo: .caption2, maximum: 1.4)
                .foregroundStyle(selected ? Theme.accentText : Theme.tertiary)
              ZStack {
                Color.clear
                if selected {
                  Capsule().fill(Theme.accent)
                    .matchedGeometryEffect(id: "day", in: selection)
                }
              }.frame(width: 24, height: 3).padding(.top, 3)
            }
            .foregroundStyle(selected ? Theme.ink : Theme.secondary)
            .frame(width: dayWidth).padding(.top, 9).padding(.bottom, 5)
            .background(selected ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
          }
          .buttonStyle(PressStyle(scale: 0.97))
          .accessibilityLabel("\(CivilDate.display(day.date, format: "EEEE d MMMM")), day \(index + 1) of \(trip.days.count)\(trip.isToday(day) ? ", today" : "")")
          .accessibilityAddTraits(selected ? .isSelected : [])
          .accessibilityIdentifier("day.date.\(index + 1)")
          .id(day.id)
        }
      }.scrollTargetLayout()
    }
    .scrollIndicators(.hidden)
    .frame(height: dayWidth + 4)
    .contentMargins(.horizontal, max(0, (carouselWidth - dayWidth) / 2), for: .scrollContent)
    .scrollTargetBehavior(.viewAligned)
    .scrollPosition(id: $carouselID, anchor: .center)
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { carouselWidth = $0 }
    .onScrollPhaseChange { _, phase in
      if phase == .interacting { browsingDates = true }
      if phase == .idle && browsingDates {
        browsingDates = false
        if let carouselID { select(carouselID, in: trip) }
      }
    }
    .onChange(of: attachment.id, initial: true) { previous, current in
      guard !browsingDates else { return }
      withAnimation(previous == current || reduceMotion ? nil : .snappy(duration: 0.28)) {
        carouselID = current
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Trip dates")
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: move(1, in: trip)
      case .decrement: move(-1, in: trip)
      @unknown default: break
      }
    }
    .padding(.bottom, 8)
  }

  private func relativeLabel(_ day: TripDay, trip: TripSnapshot) -> String {
    switch CivilDate.days(from: CivilDate.today(timeZone: trip.timeZone), to: day.date) {
    case -1: "Yesterday"
    case 0: "Today"
    case 1: "Tomorrow"
    default: CivilDate.display(day.date, format: "EEEE")
    }
  }

  private func daySelection(_ trip: TripSnapshot) -> Binding<String> {
    Binding(get: { attachment.id }, set: { select($0, in: trip, animated: false) })
  }

  private func select(_ id: String, in trip: TripSnapshot, animated: Bool = true) {
    guard id != attachment.id, trip.days.contains(where: { $0.id == id }) else { return }
    Haptics.selection()
    withAnimation(animated && !reduceMotion ? .snappy(duration: 0.28) : nil) {
      model.openDay(.init(kind: .day, id: id))
    }
  }

  private func move(_ delta: Int, in trip: TripSnapshot) {
    guard let index = trip.days.firstIndex(where: { $0.id == attachment.id }),
      trip.days.indices.contains(index + delta) else { return }
    select(trip.days[index + delta].id, in: trip)
  }
}
