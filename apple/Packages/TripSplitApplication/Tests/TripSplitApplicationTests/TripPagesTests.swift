import Foundation
import Testing
import TripSplitCompanion
import TripSplitDomain
import TripSplitWatchModel

@testable import TripSplitApplication

@MainActor struct TripPagesTests {
  /// You, Maya and Tom, where Tom owes Maya £92 and owes you £66.
  func trip() throws -> TripSnapshot {
    var draft = OnboardingDraft()
    draft.stops = [Destination.all[0].stop()]
    var trip = try draft.makeTrip()
    let you = trip.currentTravellerId
    let maya = Traveller(name: "Maya", hue: 250)
    let tom = Traveller(name: "Tom", hue: 75)
    trip.travellers += [maya, tom]
    trip.expenses = [
      expense(trip, title: "Dinner", amount: "18400", by: maya.id, with: [maya.id, tom.id]),
      expense(trip, title: "Tickets", amount: "13200", by: you, with: [you, tom.id]),
    ]
    return trip
  }

  func expense(
    _ trip: TripSnapshot, title: String, amount: String, by payer: String, with people: [String]
  ) -> Expense {
    .init(
      attachment: .init(kind: .day, id: trip.days[0].id), title: title, category: .food,
      amountMinor: amount, currency: trip.homeCurrency, status: .paid, paidOn: trip.startsOn,
      paidBy: payer, splitWith: people)
  }

  func id(_ name: String, in trip: TripSnapshot) -> String {
    trip.travellers.first { $0.name == name }!.id
  }

  @Test func peopleLeadWithWhoeverOwesMost() throws {
    let pages = TripPages(trip: try trip(), now: Date())
    #expect(pages.people.map { pages.name($0.id) } == ["Tom", "Maya", "You"])
    #expect(pages.people.map(pages.status) == ["owes £158", "is owed £92", "are owed £66"])
  }

  @Test func personLeadsWithWhatIsBetweenThemAndYou() throws {
    let trip = try trip()
    let pages = TripPages(trip: trip, now: Date())
    let tom = pages.person(id("Tom", in: trip))
    #expect(tom.headline == "Tom owes you £66")
    #expect(tom.detail == "and Maya £92")
    #expect(tom.settlement?.amount == 6600)
    let maya = pages.person(id("Maya", in: trip))
    #expect(maya.headline == "Tom owes Maya £92")
    #expect(maya.detail == nil)
    #expect(maya.settlement == nil)
    let row = try #require(pages.settlements.first { $0.to == pages.you })
    #expect(pages.subject(of: row) == id("Tom", in: trip))
  }

  @Test func personWaitsForConversionsBeforeSettlingUp() throws {
    var trip = try trip()
    trip.expenses.append(
      .init(
        attachment: .init(kind: .day, id: trip.days[0].id), title: "Lunch", category: .food,
        amountMinor: "2000", currency: "JPY", status: .paid, paidOn: trip.startsOn,
        paidBy: trip.currentTravellerId, splitWith: trip.travellers.map(\.id)))
    let pages = TripPages(trip: trip, now: Date())
    #expect(!pages.balancesComplete)
    #expect(pages.person(id("Tom", in: trip)).settlement == nil)
  }

  @Test func markPaidSettlesThroughThePhone() throws {
    let trip = try trip()
    var sent: [CompanionCommand] = []
    let model = WatchModel(
      mirror: CompanionMirror(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
      send: { sent.append($0) })
    model.receive(.init(trips: [trip], sentAt: Date()))
    let tom = id("Tom", in: trip)
    let settlement = try #require(model.pages(for: trip).person(tom).settlement)
    model.markPaid(settlement, in: trip)
    guard case .saveRepayment(_, let repayment) = sent.first else {
      Issue.record("Expected a repayment, got \(sent)")
      return
    }
    #expect(repayment.fromTravellerId == tom)
    #expect(repayment.toTravellerId == trip.currentTravellerId)
    #expect(repayment.amountMinor == "6600")
    // The watch shows it settled straight away, before the phone echoes it back.
    let pages = model.pages(for: try #require(model.trip(trip.id)))
    #expect(pages.person(tom).headline == "Tom owes Maya £92")
    #expect(pages.person(tom).settlement == nil)
  }

  @Test func pagesFollowWhereTheTripIsUp() throws {
    let model = try WatchModel.demo()
    let timeline = model.timeline
    let now = try #require(timeline.now.first)
    #expect(model.pages(for: now).pages == [.today, .budget, .balances, .days])
    #expect(try model.pages(for: #require(timeline.upcoming.first)).pages == [.budget, .balances, .days])
    #expect(try model.pages(for: #require(timeline.past.first)).pages == [.budget, .balances])
  }

  @Test func daysRunNewestFirstThenWhatsToCome() throws {
    let model = try WatchModel.demo()
    let trip = try #require(model.timeline.now.first)
    let rows = model.pages(for: trip).dayRows
    let today = try #require(trip.currentDay(at: model.now))
    #expect(rows.started.first?.id == today.id)
    #expect(rows.started.first?.isToday == true)
    #expect(rows.started.map(\.number) == Array((1...trip.dayNumber(of: today)).reversed()))
    #expect(rows.upcoming.map(\.number) == Array((trip.dayNumber(of: today) + 1)...trip.days.count))
    #expect(rows.upcoming.allSatisfy { !$0.hasStarted && !$0.isToday })
  }

  @Test func daysMarkSpendsTheWatchHasntSynced() throws {
    let model = try WatchModel.demo()
    let trip = try #require(model.timeline.now.first)
    let today = try #require(trip.currentDay(at: model.now))
    var coffee = expense(
      trip, title: "Coffee", amount: "300", by: trip.currentTravellerId, with: [trip.currentTravellerId])
    coffee.attachment = .init(kind: .day, id: today.id)
    model.send(.saveExpense(tripID: trip.id, expense: coffee))
    let pages = model.pages(for: try #require(model.trip(trip.id)))
    #expect(pages.unsynced == [coffee.id])
    #expect(pages.dayRows.started.first?.hasUnsynced == true)
    #expect(pages.dayRows.started.dropFirst().allSatisfy { !$0.hasUnsynced })
  }

  @Test func wholeAmountsRoundToTheNearestUnit() {
    #expect(WatchCurrency.whole(15_849, "GBP") == "£158")
    #expect(WatchCurrency.whole(15_850, "GBP") == "£159")
    #expect(WatchCurrency.whole(1_200_000, "JPY") == "¥1,200,000")
  }
}
