import Foundation
import TripSplitDomain
import TripSplitNetworking
import TripSplitPersistence
import TripSplitSync

@MainActor public enum DemoData {
  /// Approximate GBP reference rates so demo builds can show indicative conversions offline.
  public static func referenceRates() -> FXTable {
    let today = CivilDate.today(timeZone: TimeZone.current.identifier)
    return FXTable(
      base: "GBP", requestedDate: today, rateDate: today, source: "demo",
      rates: [
        "GBP": "1", "EUR": "1.16", "USD": "1.27", "AUD": "1.95", "CAD": "1.74", "CHF": "1.12",
        "JPY": "192", "THB": "44.2", "VND": "33000", "IDR": "20500", "MXN": "23.5", "MAD": "12.6",
        "ISK": "175", "NZD": "2.14",
      ])
  }

  public static func install(into store: LocalStore) throws {
    let today = CivilDate.today(timeZone: TimeZone.current.identifier)
    var draft = OnboardingDraft()
    draft.stops = [
      Destination.all[0].stop(nights: 3), Destination.all[1].stop(nights: 2),
      Destination.all[2].stop(nights: 2),
    ]
    draft.startsOn = CivilDate.adding(-3, to: today)
    draft.name = "Lisbon, Porto & Seville"
    draft.travellers += [Traveller(name: "Maya", hue: 250), Traveller(name: "Tom", hue: 75)]
    draft.budget = "2400"
    let trip = try draft.makeTrip()
    try store.create(trip)
    let samples: [(String, ExpenseCategory, String, Expense.Status, Int, Int)] = [
      ("Flights to Lisbon", .flight, "32700", .paid, 0, -1),
      ("Our little apartment", .stay, "62000", .paid, 1, 0),
      ("Pastéis & flat whites", .coffee, "640", .paid, 0, 3),
      ("Lunch by the river", .food, "4800", .paid, 1, 3),
      ("Tram 28 tickets", .transport, "930", .planned, 2, 3),
      ("Train to Porto", .train, "9600", .planned, 0, 4),
      ("A very good dinner", .food, "8700", .paid, 2, 2),
    ]
    for (title, category, amount, status, payer, day) in samples {
      let attachment =
        day < 0
        ? Attachment(kind: .leg, id: trip.legs[0].id) : .init(kind: .day, id: trip.days[day].id)
      let home = try Money.convert(Money.minor(amount)!, from: "EUR", to: "GBP", rate: "0.862")
      let expense = Expense(
        attachment: attachment, title: title, category: category, amountMinor: amount,
        currency: "EUR", status: status, paidOn: status == .paid ? trip.date(for: attachment) : nil,
        paidBy: trip.travellers[payer].id, splitWith: trip.travellers.map(\.id),
        conversion: Conversion(
          homeAmountMinor: String(home), rate: "0.862", rateDate: today,
          source: "Demo manual estimate", kind: "manual", quoteId: nil))
      try store.saveExpense(expense, tripID: trip.id)
    }
    var future = OnboardingDraft()
    future.stops = [Destination.all[6].stop(nights: 5), Destination.all[7].stop(nights: 4)]
    future.startsOn = CivilDate.adding(49, to: today)
    future.name = "Tokyo & Kyoto"
    future.travellers += [Traveller(name: "Maya", hue: 250)]
    future.budget = "4200"
    try store.create(future.makeTrip())
    var past = OnboardingDraft()
    past.stops = [Destination.all[4].stop(nights: 3)]
    past.startsOn = CivilDate.adding(-120, to: today)
    past.name = "Paris in June"
    try store.create(past.makeTrip())
    past = OnboardingDraft()
    past.stops = [Destination.all[5].stop(nights: 4)]
    past.startsOn = CivilDate.adding(-200, to: today)
    past.name = "A Roman holiday"
    try store.create(past.makeTrip())
  }
}
