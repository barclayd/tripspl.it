import Foundation

extension TripSnapshot {
  /// Only the inline home shortcut is conditional. Converter navigation stays available.
  var showsHomeConverter: Bool { showsHomeConverter(on: today) }

  func showsHomeConverter(on date: String) -> Bool {
    guard phase(on: date) == .now,
      let day = days.first(where: { $0.date == date }),
      let stop = stops.first(where: { $0.id == day.stopId })
    else { return false }
    return stop.currency != homeCurrency
  }

  var conversionDefaults: (from: ConversionCurrency, to: ConversionCurrency) {
    conversionDefaults(on: today)
  }

  func conversionDefaults(on date: String) -> (from: ConversionCurrency, to: ConversionCurrency) {
    let day = days.first(where: { $0.date == date }) ?? days.first
    let stop = stops.first(where: { $0.id == day?.stopId }) ?? stops.first
    let home = ConversionCurrency.forCurrency(
      homeCurrency, preferredCountryCode: Locale.current.region?.identifier)
    return (stop.map(ConversionCurrency.forStop) ?? home, home)
  }
}
