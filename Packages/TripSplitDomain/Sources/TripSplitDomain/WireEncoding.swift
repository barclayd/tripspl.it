import Foundation

// These nullable properties are required JSON keys. Swift's synthesized encodeIfPresent
// would omit them and fail the strict shared transport schema.
extension TravelLeg {
  enum CodingKeys: String, CodingKey { case id, kind, date, fromStopId, toStopId, dayId }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(kind, forKey: .kind)
    try c.encode(date, forKey: .date)
    try c.encode(fromStopId, forKey: .fromStopId)
    try c.encode(toStopId, forKey: .toStopId)
    try c.encode(dayId, forKey: .dayId)
  }
}
extension Conversion {
  enum CodingKeys: String, CodingKey { case homeAmountMinor, rate, rateDate, source, kind, quoteId }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(homeAmountMinor, forKey: .homeAmountMinor)
    try c.encode(rate, forKey: .rate)
    try c.encode(rateDate, forKey: .rateDate)
    try c.encode(source, forKey: .source)
    try c.encode(kind, forKey: .kind)
    try c.encode(quoteId, forKey: .quoteId)
  }
}
extension Expense {
  enum CodingKeys: String, CodingKey {
    case id, revision, attachment, title, category, amountMinor, currency, status, paidOn, paidBy,
      splitWith, conversion
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(revision, forKey: .revision)
    try c.encode(attachment, forKey: .attachment)
    try c.encode(title, forKey: .title)
    try c.encode(category, forKey: .category)
    try c.encode(amountMinor, forKey: .amountMinor)
    try c.encode(currency, forKey: .currency)
    try c.encode(status, forKey: .status)
    try c.encode(paidOn, forKey: .paidOn)
    try c.encode(paidBy, forKey: .paidBy)
    try c.encode(splitWith, forKey: .splitWith)
    try c.encode(conversion, forKey: .conversion)
  }
}
extension Repayment {
  enum CodingKeys: String, CodingKey {
    case id, revision, fromTravellerId, toTravellerId, amountMinor, currency, paidOn, conversion,
      note
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(revision, forKey: .revision)
    try c.encode(fromTravellerId, forKey: .fromTravellerId)
    try c.encode(toTravellerId, forKey: .toTravellerId)
    try c.encode(amountMinor, forKey: .amountMinor)
    try c.encode(currency, forKey: .currency)
    try c.encode(paidOn, forKey: .paidOn)
    try c.encode(conversion, forKey: .conversion)
    try c.encode(note, forKey: .note)
  }
}
extension SyncRequest {
  enum CodingKeys: String, CodingKey { case cursor, syncEpoch, operations }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(cursor, forKey: .cursor)
    try c.encode(syncEpoch, forKey: .syncEpoch)
    try c.encode(operations, forKey: .operations)
  }
}
