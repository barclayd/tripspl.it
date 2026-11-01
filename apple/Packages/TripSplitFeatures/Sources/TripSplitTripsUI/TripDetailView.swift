import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitSharedUI

public struct TripDetailView: View {
  public init(tripID: String, compact: Bool = false) {
    self.tripID = tripID
    self.compact = compact
  }
  @Environment(AppModel.self) private var model
  var tripID: String
  /// The Duo's trip column, which leaves the passes and cost card to the wider panes.
  var compact = false
  @State private var section = Section.days
  @State private var repayment: Settlement?

  private enum Section: Hashable { case days, balances }

  public var body: some View {
    if let trip = model.store.trip(tripID) {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          if !compact {
            header(trip)
            BoardingPassStack(trip: trip) { model.openDay(.init(kind: .leg, id: $0.id)) }
            TripCostCard(trip: trip)
          }
          SyncNotice(tripID: trip.id)
          SegmentedControl(
            "Trip section", selection: $section,
            options: [(.days, "Days"), (.balances, "Who owes who")])
          Group {
            switch section {
            case .days: TripDaysList(trip: trip, compact: compact)
            case .balances: TripBalances(trip: trip) { repayment = $0 }
            }
          }
          .transition(.opacity)
          .id(section)
        }
        .pagePadding()
        .padding(.bottom, 48)
      }
      .background(Theme.background)
      .navigationTitle("")
      .navigationBarTitleDisplayMode(.inline)
      .sheet(item: $repayment) { settlement in
        RepaymentView(tripID: trip.id, settlement: settlement)
      }
    }
  }

  private func header(_ trip: TripSnapshot) -> some View {
    let people = trip.activeTravellers
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        ForEach(Array(trip.uniqueFlags.enumerated()), id: \.offset) { index, flag in
          Text(flag).font(.system(size: 40)).popIn(delay: 0.15 + Double(index) * 0.1)
        }
      }
      .accessibilityHidden(true)
      Text(trip.name)
        .typeface(30, .heavy, tracking: -0.035, relativeTo: .largeTitle, maximum: 1.3)
        .foregroundStyle(Theme.ink)
        .lineSpacing(-2)
        .padding(.top, 14)
        .accessibilityAddTraits(.isHeader)
      HStack(spacing: 10) {
        HStack(spacing: -7) {
          ForEach(people) { person in
            Avatar(traveller: person, size: 28)
              .background(Circle().fill(Theme.background).padding(-2))
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(people.map(\.name).formatted(.list(type: .and)))
        Text(
          "\(CivilDate.display(trip.startsOn)) – \(CivilDate.display(trip.endsOn)) · \(trip.days.count) day\(trip.days.count == 1 ? "" : "s")"
        )
        .typeface(14, relativeTo: .subheadline)
        .foregroundStyle(Theme.secondary)
      }
      .padding(.top, 10)
    }
  }
}
