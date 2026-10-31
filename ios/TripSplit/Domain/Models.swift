import Foundation

struct Traveller: Codable, Identifiable, Hashable, Sendable {
  var id: String = UUID().uuidString
  var name: String
  var hue: Double = 350
  var archived = false
  var revision = 0
}
struct Stop: Codable, Identifiable, Hashable, Sendable {
  var id: String = UUID().uuidString
  var countryCode: String
  var place: String
  var nights: Int
  var currency: String
  var latitude: Double
  var longitude: Double
  var flag: String { countryCode.flag }
  var code: String {
    [
      "Lisbon": "LIS", "Porto": "OPO", "Seville": "SVQ", "London": "LHR", "Tokyo": "TYO",
      "Paris": "CDG", "New York": "NYC", "Rome": "ROM", "Barcelona": "BCN",
    ][place] ?? String(place.prefix(3)).uppercased()
  }
}
struct TripDay: Codable, Identifiable, Hashable, Sendable {
  var id: String = UUID().uuidString
  var date: String
  var stopId: String
}
struct TravelLeg: Codable, Identifiable, Hashable, Sendable {
  enum Kind: String, Codable, Sendable { case outbound, transfer, `return` }
  var id: String = UUID().uuidString
  var kind: Kind
  var date: String
  var fromStopId: String?
  var toStopId: String?
  var dayId: String?
  var title: String {
    switch kind {
    case .outbound: "Getting there"
    case .transfer: "On the move"
    case .return: "Getting home"
    }
  }
}
struct Attachment: Codable, Hashable, Identifiable, Sendable {
  enum Kind: String, Codable, Sendable { case day, leg }
  var kind: Kind
  var id: String
}
struct Conversion: Codable, Hashable, Sendable {
  var homeAmountMinor: String
  var rate: String
  var rateDate: String
  var source: String
  var kind: String
  var quoteId: String?
}
enum ExpenseCategory: String, CaseIterable, Codable, Sendable {
  case food, coffee, stay, activity, transport, shopping, flight, train, taxi, other
  var title: String {
    switch self {
    case .food: "Food"
    case .coffee: "Coffee"
    case .stay: "Stay"
    case .activity: "Things to do"
    case .transport: "Getting around"
    case .shopping: "Shopping"
    case .flight: "Flight"
    case .train: "Train"
    case .taxi: "Taxi"
    case .other: "Other"
    }
  }
  var symbol: String {
    switch self {
    case .food: "fork.knife"
    case .coffee: "cup.and.saucer"
    case .stay: "bed.double"
    case .activity: "ticket"
    case .transport: "tram"
    case .shopping: "bag"
    case .flight: "airplane"
    case .train: "train.side.front.car"
    case .taxi: "car"
    case .other: "ellipsis"
    }
  }
  var hue: Double {
    switch self {
    case .food: 0.10
    case .coffee: 0.13
    case .stay: 0.77
    case .activity: 0.48
    case .transport: 0.60
    case .shopping: 0.91
    case .flight: 0.62
    case .train: 0.40
    case .taxi: 0.20
    case .other: 0.06
    }
  }
}
struct Expense: Codable, Identifiable, Hashable, Sendable {
  enum Status: String, Codable, CaseIterable, Sendable { case planned, paid }
  var id: String = UUID().uuidString
  var revision = 0
  var attachment: Attachment
  var title: String
  var category: ExpenseCategory
  var amountMinor: String
  var currency: String
  var status: Status
  var paidOn: String?
  var paidBy: String
  var splitWith: [String]
  var conversion: Conversion?
  func homeMinor(in currency: String) -> Int64? {
    Money.minor(self.currency == currency ? amountMinor : conversion?.homeAmountMinor)
  }
}
struct Repayment: Codable, Identifiable, Hashable, Sendable {
  var id: String = UUID().uuidString
  var revision = 0
  var fromTravellerId: String
  var toTravellerId: String
  var amountMinor: String
  var currency: String
  var paidOn: String
  var conversion: Conversion?
  var note: String
}
struct TripSnapshot: Codable, Identifiable, Hashable, Sendable {
  var id: String = UUID().uuidString
  var revision = 0
  var syncEpoch = "local"
  var name: String
  var startsOn: String
  var timeZone: String
  var homeCurrency: String
  var budgetMinor: String
  var ownerTravellerId: String
  var currentTravellerId: String
  var role = "owner"
  var travellers: [Traveller]
  var stops: [Stop]
  var days: [TripDay]
  var legs: [TravelLeg]
  var expenses: [Expense] = []
  var repayments: [Repayment] = []
  var archived = false
  var updatedAt = ISO8601DateFormatter().string(from: Date())
  var endsOn: String { days.last?.date ?? startsOn }
  var today: String { CivilDate.today(timeZone: timeZone) }
  var phase: Phase { phase(on: today) }
  enum Phase: String, CaseIterable { case now, upcoming, past }
  func phase(on day: String) -> Phase { day < startsOn ? .upcoming : day > endsOn ? .past : .now }
  var flags: String { stops.map(\.flag).joined(separator: " ") }
  var activeTravellers: [Traveller] { travellers.filter { !$0.archived } }
  var currentAttachment: Attachment {
    .init(kind: .day, id: days.first(where: { $0.date == today })?.id ?? days.first?.id ?? "")
  }
  func date(for attachment: Attachment) -> String {
    attachment.kind == .day
      ? days.first(where: { $0.id == attachment.id })?.date ?? startsOn
      : legs.first(where: { $0.id == attachment.id })?.date ?? startsOn
  }
  func stop(for attachment: Attachment) -> Stop? {
    let id =
      attachment.kind == .day
      ? days.first(where: { $0.id == attachment.id })?.stopId
      : legs.first(where: { $0.id == attachment.id })?.toStopId
    return stops.first { $0.id == id }
  }
  func title(for attachment: Attachment) -> String {
    attachment.kind == .leg
      ? legs.first(where: { $0.id == attachment.id })?.title ?? "Travel"
      : CivilDate.display(date(for: attachment), format: "EEEE d MMMM")
  }
  func expenses(for attachment: Attachment) -> [Expense] {
    expenses.filter { $0.attachment == attachment }
  }
}
struct TripSettings: Codable, Hashable, Sendable {
  var name: String
  var startsOn: String
  var timeZone: String
  var homeCurrency: String
  var budgetMinor: String
  var stops: [Stop]
  var days: [TripDay]
  var legs: [TravelLeg]
  init(_ trip: TripSnapshot) {
    name = trip.name
    startsOn = trip.startsOn
    timeZone = trip.timeZone
    homeCurrency = trip.homeCurrency
    budgetMinor = trip.budgetMinor
    stops = trip.stops
    days = trip.days
    legs = trip.legs
  }
}
struct Operation: Codable, Identifiable, Hashable, Sendable {
  var id: String = UUID().uuidString
  var syncEpoch: String
  var type: String
  var entityId: String
  var expectedRevision: Int?
  var payload: Payload
  enum Payload: Codable, Hashable, Sendable {
    case expense(Expense)
    case repayment(Repayment)
    case traveller(Traveller)
    case settings(TripSettings)
    case archive(Bool)
    case none
    init(from decoder: Decoder) throws {
      let c = try decoder.singleValueContainer()
      if c.decodeNil() {
        self = .none
      } else if let v = try? c.decode(Expense.self) {
        self = .expense(v)
      } else if let v = try? c.decode(Repayment.self) {
        self = .repayment(v)
      } else if let v = try? c.decode(TripSettings.self) {
        self = .settings(v)
      } else if let v = try? c.decode(Traveller.self) {
        self = .traveller(v)
      } else {
        self = .archive(try c.decode([String: Bool].self)["archived"] ?? false)
      }
    }
    func encode(to encoder: Encoder) throws {
      var c = encoder.singleValueContainer()
      switch self {
      case .expense(let v): try c.encode(v)
      case .repayment(let v): try c.encode(v)
      case .traveller(let v): try c.encode(v)
      case .settings(let v): try c.encode(v)
      case .archive(let v): try c.encode(["archived": v])
      case .none: try c.encodeNil()
      }
    }
  }
  // A null expectedRevision is part of the wire contract for insert operations.
  enum CodingKeys: String, CodingKey {
    case id, syncEpoch, type, entityId, expectedRevision, payload
  }
  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(syncEpoch, forKey: .syncEpoch)
    try c.encode(type, forKey: .type)
    try c.encode(entityId, forKey: .entityId)
    try c.encode(expectedRevision, forKey: .expectedRevision)
    try c.encode(payload, forKey: .payload)
  }
  func apply(to trip: inout TripSnapshot) {
    switch payload {
    case .expense(let v):
      trip.expenses.removeAll { $0.id == entityId }
      trip.expenses.append(v)
    case .repayment(let v):
      trip.repayments.removeAll { $0.id == entityId }
      trip.repayments.append(v)
    case .traveller(let v):
      trip.travellers.removeAll { $0.id == entityId }
      trip.travellers.append(v)
    case .settings(let v):
      trip.name = v.name
      trip.startsOn = v.startsOn
      trip.timeZone = v.timeZone
      trip.homeCurrency = v.homeCurrency
      trip.budgetMinor = v.budgetMinor
      trip.stops = v.stops
      trip.days = v.days
      trip.legs = v.legs
    case .archive(let v): trip.archived = v
    case .none:
      if type == "expense.delete" { trip.expenses.removeAll { $0.id == entityId } }
      if type == "repayment.delete" { trip.repayments.removeAll { $0.id == entityId } }
    }
  }
}
struct OperationResult: Codable, Sendable {
  var id: String
  var status: String
  var revision: Int?
  var code: String?
  var message: String?
}
struct SyncRequest: Codable, Sendable {
  var cursor: Int?
  var syncEpoch: String?
  var operations: [Operation]
}
struct SyncResponse: Codable, Sendable {
  var cursor: Int
  var syncEpoch: String
  var snapshot: TripSnapshot?
  var results: [OperationResult]
}
struct Account: Codable, Sendable {
  var id: String
  var displayName: String
}
struct Session: Codable, Sendable {
  var user: Account
  var accessToken: String
  var refreshToken: String
  var expiresAt: String
}
struct AuthChallenge: Codable, Sendable {
  var id: String
  var nonce: String
  var expiresAt: String
}
struct FXQuote: Codable, Sendable {
  var id: String
  var from: String
  var to: String
  var rate: String
  var requestedDate: String
  var rateDate: String
  var source: String
}
struct Invite: Codable, Identifiable, Sendable {
  var id: String
  var token: String
  var expiresAt: String
  var url: String?
}
extension String {
  var flag: String {
    unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map(String.init).joined()
  }
}
