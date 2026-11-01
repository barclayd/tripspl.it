import Foundation

extension TripSnapshot {
  /// Only the inline home shortcut is conditional. Converter navigation stays available.
  public var showsHomeConverter: Bool {
    guard phase == .now, let stop = stop(for: currentAttachment) else { return false }
    return stop.currency != homeCurrency
  }

  /// A day at a stop that spends another currency, where converting earns a place in the rail.
  public func isAbroad(_ attachment: Attachment) -> Bool {
    guard attachment.kind == .day, let stop = stop(for: attachment) else { return false }
    return stop.currency != homeCurrency
  }

  public func showsHomeConverter(on date: String) -> Bool {
    guard phase(on: date) == .now,
      let day = days.first(where: { $0.date == date }),
      let stop = stops.first(where: { $0.id == day.stopId })
    else { return false }
    return stop.currency != homeCurrency
  }

  public var conversionDefaults: (from: ConversionCurrency, to: ConversionCurrency) {
    let home = ConversionCurrency.forCurrency(
      homeCurrency, preferredCountryCode: Locale.current.region?.identifier)
    return (stop(for: currentAttachment).map(ConversionCurrency.forStop) ?? home, home)
  }

  public func conversionDefaults(on date: String) -> (
    from: ConversionCurrency, to: ConversionCurrency
  ) {
    let day = days.first(where: { $0.date == date }) ?? days.first
    let stop = stops.first(where: { $0.id == day?.stopId }) ?? stops.first
    let home = ConversionCurrency.forCurrency(
      homeCurrency, preferredCountryCode: Locale.current.region?.identifier)
    return (stop.map(ConversionCurrency.forStop) ?? home, home)
  }
}
