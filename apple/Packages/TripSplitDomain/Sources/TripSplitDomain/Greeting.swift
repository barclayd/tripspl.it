import Foundation

/// What the app says on the day you set off, shared by onboarding and the countdown widget.
public enum Greeting {
  /// "Bon voyage!" in the language of the first stop.
  public static func departure(countryCode: String?) -> String {
    switch countryCode?.uppercased() {
    case "PT": "Boa viagem!"
    case "ES", "MX": "¡Buen viaje!"
    case "IT": "Buon viaggio!"
    case "GR": "Kaló taxídi!"
    case "HR": "Sretan put!"
    case "CH", "DE", "AT": "Gute Reise!"
    case "IS": "Góða ferð!"
    case "JP": "Itterasshai!"
    case "TH": "Tiao hai sanuk!"
    case "VN": "Thượng lộ bình an!"
    case "ID": "Selamat jalan!"
    case "US": "Have a great trip!"
    case "MA": "Bslama!"
    case "AU": "Have a ripper trip!"
    default: "Bon voyage!"
    }
  }
}
