import Foundation

public struct Traveller: Codable, Identifiable, Hashable, Sendable {
  public init(
    id: String = UUID().uuidString,
    name: String,
    hue: Double = 350,
    archived: Bool = false,
    revision: Int = 0
  ) {
    self.id = id
    self.name = name
    self.hue = hue
    self.archived = archived
    self.revision = revision
  }
  public var id: String = UUID().uuidString
  public var name: String
  public var hue: Double = 350
  public var archived = false
  public var revision = 0
}
public struct Stop: Codable, Identifiable, Hashable, Sendable {
  public init(
    id: String = UUID().uuidString,
    countryCode: String,
    place: String,
    nights: Int,
    currency: String,
    latitude: Double,
    longitude: Double,
    timeZone: String? = nil
  ) {
    self.id = id
    self.countryCode = countryCode
    self.place = place
    self.nights = nights
    self.currency = currency
    self.latitude = latitude
    self.longitude = longitude
    self.timeZone = timeZone
  }
  public var id: String = UUID().uuidString
  public var countryCode: String
  public var place: String
  public var nights: Int
  public var currency: String
  public var latitude: Double
  public var longitude: Double
  public var timeZone: String? = nil
  public var resolvedTimeZone: String? {
    if let timeZone, TimeZone(identifier: timeZone) != nil { return timeZone }
    return DestinationTimeZones.identifier(
      countryCode: countryCode, latitude: latitude, longitude: longitude)
  }
  public var flag: String { countryCode.flag }
  public var code: String {
    [
      "Lisbon": "LIS", "Porto": "OPO", "Seville": "SVQ", "London": "LHR", "Tokyo": "TYO",
      "Paris": "CDG", "New York": "NYC", "Rome": "ROM", "Barcelona": "BCN",
    ][place] ?? String(place.prefix(3)).uppercased()
  }
}
public struct TripDay: Codable, Identifiable, Hashable, Sendable {
  public init(
    id: String = UUID().uuidString,
    date: String,
    stopId: String
  ) {
    self.id = id
    self.date = date
    self.stopId = stopId
  }
  public var id: String = UUID().uuidString
  public var date: String
  public var stopId: String
}
public struct TravelLeg: Codable, Identifiable, Hashable, Sendable {
  public init(
    id: String = UUID().uuidString,
    kind: Kind,
    date: String,
    fromStopId: String? = nil,
    toStopId: String? = nil,
    dayId: String? = nil
  ) {
    self.id = id
    self.kind = kind
    self.date = date
    self.fromStopId = fromStopId
    self.toStopId = toStopId
    self.dayId = dayId
  }
  public enum Kind: String, Codable, Sendable { case outbound, transfer, `return` }
  public var id: String = UUID().uuidString
  public var kind: Kind
  public var date: String
  public var fromStopId: String?
  public var toStopId: String?
  public var dayId: String?
  public var title: String {
    switch kind {
    case .outbound: "Getting there"
    case .transfer: "On the move"
    case .return: "Getting home"
    }
  }
}
public struct Attachment: Codable, Hashable, Identifiable, Sendable {
  public init(
    kind: Kind,
    id: String
  ) {
    self.kind = kind
    self.id = id
  }
  public enum Kind: String, Codable, Sendable { case day, leg }
  public var kind: Kind
  public var id: String
}
public struct Conversion: Codable, Hashable, Sendable {
  public init(
    homeAmountMinor: String,
    rate: String,
    rateDate: String,
    source: String,
    kind: String,
    quoteId: String? = nil
  ) {
    self.homeAmountMinor = homeAmountMinor
    self.rate = rate
    self.rateDate = rateDate
    self.source = source
    self.kind = kind
    self.quoteId = quoteId
  }
  public var homeAmountMinor: String
  public var rate: String
  public var rateDate: String
  public var source: String
  public var kind: String
  public var quoteId: String?
}
public enum ExpenseCategory: String, CaseIterable, Codable, Sendable {
  case food, coffee, stay, activity, transport, shopping, flight, train, taxi, other
  public var title: String {
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
  public var symbol: String {
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
  public var hue: Double {
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
public struct Expense: Codable, Identifiable, Hashable, Sendable {
  public init(
    id: String = UUID().uuidString,
    revision: Int = 0,
    attachment: Attachment,
    title: String,
    category: ExpenseCategory,
    amountMinor: String,
    currency: String,
    status: Status,
    paidOn: String? = nil,
    paidBy: String,
    splitWith: [String],
    conversion: Conversion? = nil,
    returnPairId: String? = nil
  ) {
    self.id = id
    self.revision = revision
    self.attachment = attachment
    self.title = title
    self.category = category
    self.amountMinor = amountMinor
    self.currency = currency
    self.status = status
    self.paidOn = paidOn
    self.paidBy = paidBy
    self.splitWith = splitWith
    self.conversion = conversion
    self.returnPairId = returnPairId
  }
  public enum Status: String, Codable, CaseIterable, Sendable { case planned, paid }
  public var id: String = UUID().uuidString
  public var revision = 0
  public var attachment: Attachment
  public var title: String
  public var category: ExpenseCategory
  public var amountMinor: String
  public var currency: String
  public var status: Status
  public var paidOn: String?
  public var paidBy: String
  public var splitWith: [String]
  public var conversion: Conversion?
  /// Shared by both halves of a return ticket, one on the way out and one on the way home, so
  /// they edit and delete together. See `TripSnapshot.returnHalves(of:)`.
  public var returnPairId: String?
  public func homeMinor(in currency: String) -> Int64? {
    Money.minor(self.currency == currency ? amountMinor : conversion?.homeAmountMinor)
  }
}
public struct Repayment: Codable, Identifiable, Hashable, Sendable {
  public init(
    id: String = UUID().uuidString,
    revision: Int = 0,
    fromTravellerId: String,
    toTravellerId: String,
    amountMinor: String,
    currency: String,
    paidOn: String,
    conversion: Conversion? = nil,
    note: String
  ) {
    self.id = id
    self.revision = revision
    self.fromTravellerId = fromTravellerId
    self.toTravellerId = toTravellerId
    self.amountMinor = amountMinor
    self.currency = currency
    self.paidOn = paidOn
    self.conversion = conversion
    self.note = note
  }
  public var id: String = UUID().uuidString
  public var revision = 0
  public var fromTravellerId: String
  public var toTravellerId: String
  public var amountMinor: String
  public var currency: String
  public var paidOn: String
  public var conversion: Conversion?
  public var note: String
}
/// Where a trip sets off from and returns to. Flag, pass code and currency come from the
/// country, so only the place itself travels over the wire.
public struct TripOrigin: Codable, Hashable, Sendable {
  public init(place: String, countryCode: String, latitude: Double, longitude: Double) {
    self.place = place
    self.countryCode = countryCode
    self.latitude = latitude
    self.longitude = longitude
  }
  public var place: String
  public var countryCode: String
  public var latitude: Double
  public var longitude: Double
  public var flag: String { countryCode.flag }
  /// The country's main currency, the default for a trip set off from here.
  public var currency: String? { CountryMetadata.country(countryCode)?.defaultCurrency }
}
public struct TripSnapshot: Codable, Identifiable, Hashable, Sendable {
  public init(
    id: String = UUID().uuidString,
    revision: Int = 0,
    syncEpoch: String = "local",
    name: String,
    startsOn: String,
    timeZone: String,
    homeCurrency: String,
    budgetMinor: String,
    origin: TripOrigin? = nil,
    ownerTravellerId: String,
    currentTravellerId: String,
    role: String = "owner",
    travellers: [Traveller],
    stops: [Stop],
    days: [TripDay],
    legs: [TravelLeg],
    expenses: [Expense] = [],
    repayments: [Repayment] = [],
    archived: Bool = false,
    updatedAt: String = ISO8601DateFormatter().string(from: Date())
  ) {
    self.id = id
    self.revision = revision
    self.syncEpoch = syncEpoch
    self.name = name
    self.startsOn = startsOn
    self.timeZone = timeZone
    self.homeCurrency = homeCurrency
    self.budgetMinor = budgetMinor
    self.origin = origin
    self.ownerTravellerId = ownerTravellerId
    self.currentTravellerId = currentTravellerId
    self.role = role
    self.travellers = travellers
    self.stops = stops
    self.days = days
    self.legs = legs
    self.expenses = expenses
    self.repayments = repayments
    self.archived = archived
    self.updatedAt = updatedAt
  }
  public var id: String = UUID().uuidString
  public var revision = 0
  public var syncEpoch = "local"
  public var name: String
  public var startsOn: String
  public var timeZone: String
  public var homeCurrency: String
  public var budgetMinor: String
  /// Optional and never null on the wire; older trips have none.
  public var origin: TripOrigin? = nil
  public var ownerTravellerId: String
  public var currentTravellerId: String
  public var role = "owner"
  public var travellers: [Traveller]
  public var stops: [Stop]
  public var days: [TripDay]
  public var legs: [TravelLeg]
  public var expenses: [Expense] = []
  public var repayments: [Repayment] = []
  public var archived = false
  public var updatedAt = ISO8601DateFormatter().string(from: Date())
  public var endsOn: String { days.last?.date ?? startsOn }
  /// The itinerary day you're on, or the phone's date when the trip isn't under way.
  public var today: String {
    let now = Date()
    return currentDay(at: now)?.date ?? CivilDate.string(now, timeZone: TimeZone.current.identifier)
  }
  public var phase: Phase { phase(at: Date()) }
  public enum Phase: String, CaseIterable { case now, upcoming, past }
  public func phase(on day: String) -> Phase {
    day < startsOn ? .upcoming : day > endsOn ? .past : .now
  }
  public var flags: String { stops.map(\.flag).joined(separator: " ") }
  public var activeTravellers: [Traveller] { travellers.filter { !$0.archived } }
  public var currentAttachment: Attachment {
    currentAttachment(at: Date())
  }
  public func currentAttachment(at instant: Date) -> Attachment {
    let day =
      currentDay(at: instant)
      ?? days.last(where: { $0.date <= today(for: .init(kind: .day, id: $0.id), at: instant) })
      ?? days.first
    return .init(kind: .day, id: day?.id ?? "")
  }
  /// The day under way at `instant`. Nothing starts until the phone's own date reaches the first
  /// day, so a trip planned from London waits for London's midnight, not the destination's.
  public func currentDay(
    at instant: Date, localTimeZone: String = TimeZone.current.identifier
  ) -> TripDay? {
    guard CivilDate.string(instant, timeZone: localTimeZone) >= startsOn else { return nil }
    // Crossing zones can make two itinerary dates locally current. Prefer the later stop.
    var datesByZone: [String: String] = [:]
    var datesByStop: [String: String] = [:]
    for stop in stops {
      let zone = stop.resolvedTimeZone ?? timeZone
      let date = datesByZone[zone] ?? CivilDate.string(instant, timeZone: zone)
      datesByZone[zone] = date
      datesByStop[stop.id] = date
    }
    return days.last { $0.date == datesByStop[$0.stopId] }
  }
  /// Upcoming until the phone's date reaches the start, and past once both the phone and the
  /// last destination have moved beyond the day home.
  public func phase(at instant: Date, localTimeZone: String = TimeZone.current.identifier) -> Phase {
    let local = CivilDate.string(instant, timeZone: localTimeZone)
    if local < startsOn { return .upcoming }
    if currentDay(at: instant, localTimeZone: localTimeZone) != nil { return .now }
    let lastDate = CivilDate.string(instant, timeZone: stops.last?.resolvedTimeZone ?? timeZone)
    if lastDate > endsOn, local > endsOn { return .past }
    return .now
  }
  public func timeZone(for attachment: Attachment) -> String {
    stop(for: attachment)?.resolvedTimeZone ?? timeZone
  }
  public func today(for attachment: Attachment, at instant: Date = Date()) -> String {
    CivilDate.string(instant, timeZone: timeZone(for: attachment))
  }
  public func isToday(_ day: TripDay, at instant: Date = Date()) -> Bool {
    day.date == today(for: .init(kind: .day, id: day.id), at: instant)
  }
  public func date(for attachment: Attachment) -> String {
    attachment.kind == .day
      ? days.first(where: { $0.id == attachment.id })?.date ?? startsOn
      : legs.first(where: { $0.id == attachment.id })?.date ?? startsOn
  }
  public func stop(for attachment: Attachment) -> Stop? {
    let id =
      attachment.kind == .day
      ? days.first(where: { $0.id == attachment.id })?.stopId
      : legs.first(where: { $0.id == attachment.id }).flatMap { $0.toStopId ?? $0.fromStopId }
    return stops.first { $0.id == id }
  }
  public func title(for attachment: Attachment) -> String {
    attachment.kind == .leg
      ? legs.first(where: { $0.id == attachment.id })?.title ?? "Travel"
      : CivilDate.display(date(for: attachment), format: "EEEE d MMMM")
  }
  public func expenses(for attachment: Attachment) -> [Expense] {
    expenses.filter { $0.attachment == attachment }
  }
}
public struct TripSettings: Codable, Hashable, Sendable {
  public var name: String
  public var startsOn: String
  public var timeZone: String
  public var homeCurrency: String
  public var budgetMinor: String
  /// Omitted when nil, which keeps the saved origin rather than clearing it.
  public var origin: TripOrigin?
  public var stops: [Stop]
  public var days: [TripDay]
  public var legs: [TravelLeg]
  public init(_ trip: TripSnapshot) {
    name = trip.name
    startsOn = trip.startsOn
    timeZone = trip.timeZone
    homeCurrency = trip.homeCurrency
    budgetMinor = trip.budgetMinor
    origin = trip.origin
    stops = trip.stops
    days = trip.days
    legs = trip.legs
  }
}
public struct Operation: Codable, Identifiable, Hashable, Sendable {
  public init(
    id: String = UUID().uuidString,
    syncEpoch: String,
    type: String,
    entityId: String,
    expectedRevision: Int? = nil,
    payload: Payload
  ) {
    self.id = id
    self.syncEpoch = syncEpoch
    self.type = type
    self.entityId = entityId
    self.expectedRevision = expectedRevision
    self.payload = payload
  }
  public var id: String = UUID().uuidString
  public var syncEpoch: String
  public var type: String
  public var entityId: String
  public var expectedRevision: Int?
  public var payload: Payload
  public enum Payload: Codable, Hashable, Sendable {
    case expense(Expense)
    case repayment(Repayment)
    case traveller(Traveller)
    case settings(TripSettings)
    case reschedule(TripReschedule)
    case archive(Bool)
    case none
    public init(from decoder: Decoder) throws {
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
      } else if let v = try? c.decode(TripReschedule.self) {
        self = .reschedule(v)
      } else {
        self = .archive(try c.decode([String: Bool].self)["archived"] ?? false)
      }
    }
    public func encode(to encoder: Encoder) throws {
      var c = encoder.singleValueContainer()
      switch self {
      case .expense(let v): try c.encode(v)
      case .repayment(let v): try c.encode(v)
      case .traveller(let v): try c.encode(v)
      case .settings(let v): try c.encode(v)
      case .reschedule(let v): try c.encode(v)
      case .archive(let v): try c.encode(["archived": v])
      case .none: try c.encodeNil()
      }
    }
  }
  // A null expectedRevision is part of the wire contract for insert operations.
  enum CodingKeys: String, CodingKey {
    case id, syncEpoch, type, entityId, expectedRevision, payload
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(syncEpoch, forKey: .syncEpoch)
    try c.encode(type, forKey: .type)
    try c.encode(entityId, forKey: .entityId)
    try c.encode(expectedRevision, forKey: .expectedRevision)
    try c.encode(payload, forKey: .payload)
  }
  public func apply(to trip: inout TripSnapshot) {
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
      if let origin = v.origin { trip.origin = origin }
      trip.stops = v.stops
      trip.days = v.days
      trip.legs = v.legs
    case .reschedule(let v):
      trip.startsOn = v.startsOn
      let nights = Dictionary(v.stops.map { ($0.id, $0.nights) }, uniquingKeysWith: { first, _ in first })
      for index in trip.stops.indices {
        if let value = nights[trip.stops[index].id] { trip.stops[index].nights = value }
      }
      trip.days = v.days
      trip.legs = v.legs
      // Expenses on a day that leaves go where the reschedule says, as the server moves them.
      let moves = Dictionary(
        v.moves.map { ($0.fromDayId, $0.toDayId) }, uniquingKeysWith: { first, _ in first })
      for index in trip.expenses.indices where trip.expenses[index].attachment.kind == .day {
        if let day = moves[trip.expenses[index].attachment.id] {
          trip.expenses[index].attachment.id = day
        }
      }
    case .archive(let v): trip.archived = v
    case .none:
      if type == "expense.delete" { trip.expenses.removeAll { $0.id == entityId } }
      if type == "repayment.delete" { trip.repayments.removeAll { $0.id == entityId } }
    }
  }
}
public struct OperationResult: Codable, Sendable {
  public init(
    id: String,
    status: String,
    revision: Int? = nil,
    code: String? = nil,
    message: String? = nil
  ) {
    self.id = id
    self.status = status
    self.revision = revision
    self.code = code
    self.message = message
  }
  public var id: String
  public var status: String
  public var revision: Int?
  public var code: String?
  public var message: String?
}
public struct SyncRequest: Codable, Sendable {
  public init(
    cursor: Int? = nil,
    syncEpoch: String? = nil,
    operations: [Operation]
  ) {
    self.cursor = cursor
    self.syncEpoch = syncEpoch
    self.operations = operations
  }
  public var cursor: Int?
  public var syncEpoch: String?
  public var operations: [Operation]
}
public struct SyncResponse: Codable, Sendable {
  public init(
    cursor: Int,
    syncEpoch: String,
    snapshot: TripSnapshot? = nil,
    results: [OperationResult]
  ) {
    self.cursor = cursor
    self.syncEpoch = syncEpoch
    self.snapshot = snapshot
    self.results = results
  }
  public var cursor: Int
  public var syncEpoch: String
  public var snapshot: TripSnapshot?
  public var results: [OperationResult]
}
public struct Account: Codable, Sendable {
  public init(
    id: String,
    displayName: String
  ) {
    self.id = id
    self.displayName = displayName
  }
  public var id: String
  public var displayName: String
}
public struct Session: Codable, Sendable {
  public init(
    user: Account,
    accessToken: String,
    refreshToken: String,
    expiresAt: String
  ) {
    self.user = user
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.expiresAt = expiresAt
  }
  public var user: Account
  public var accessToken: String
  public var refreshToken: String
  public var expiresAt: String
}
public struct AuthChallenge: Codable, Sendable {
  public init(
    id: String,
    nonce: String,
    expiresAt: String
  ) {
    self.id = id
    self.nonce = nonce
    self.expiresAt = expiresAt
  }
  public var id: String
  public var nonce: String
  public var expiresAt: String
}
public struct FXQuote: Codable, Sendable {
  public init(
    id: String,
    from: String,
    to: String,
    rate: String,
    requestedDate: String,
    rateDate: String,
    source: String
  ) {
    self.id = id
    self.from = from
    self.to = to
    self.rate = rate
    self.requestedDate = requestedDate
    self.rateDate = rateDate
    self.source = source
  }
  public var id: String
  public var from: String
  public var to: String
  public var rate: String
  public var requestedDate: String
  public var rateDate: String
  public var source: String
}
public struct Invite: Codable, Identifiable, Sendable {
  public init(
    id: String,
    token: String,
    expiresAt: String,
    url: String? = nil
  ) {
    self.id = id
    self.token = token
    self.expiresAt = expiresAt
    self.url = url
  }
  public var id: String
  public var token: String
  public var expiresAt: String
  public var url: String?
}
/// The outcome of `POST /trips/{tripId}/nudges`. A traveller without an account can't be
/// reached, so `notJoined` leaves their day free for when they join.
public struct NudgeResult: Codable, Hashable, Sendable {
  public enum Status: String, Codable, Sendable { case sent, notJoined }
  public init(status: Status, nudgedOn: String) {
    self.status = status
    self.nudgedOn = nudgedOn
  }
  public var status: Status
  /// The trip day the nudge counts against, in the trip's time zone.
  public var nudgedOn: String
}
/// Where APNs should deliver to: the device token as hex, and which gateway issued it.
public struct PushDevice: Codable, Hashable, Sendable {
  public enum Environment: String, Codable, Sendable { case sandbox, production }
  public init(token: String, environment: Environment) {
    self.token = token
    self.environment = environment
  }
  public var token: String
  public var environment: Environment
}
extension String {
  public var flag: String {
    unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map(String.init).joined()
  }
}
