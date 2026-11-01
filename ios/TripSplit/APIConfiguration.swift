import Foundation

/// The host app owns deployment configuration; packages receive an explicit endpoint.
enum APIConfiguration {
  static var baseURL: URL? {
    var configured =
      (Bundle.main.object(forInfoDictionaryKey: "TripSplitAPIBaseURL") as? String) ?? ""
    #if DEBUG
      let arguments = ProcessInfo.processInfo.arguments
      if let index = arguments.firstIndex(of: "--api-base-url"),
        arguments.indices.contains(index + 1)
      {
        configured = arguments[index + 1]
      }
    #endif
    if let candidate = URL(string: configured), candidate.scheme == "https" {
      return candidate
    }
    #if DEBUG
      if let candidate = URL(string: configured), candidate.scheme == "http",
        ["localhost", "127.0.0.1", "::1"].contains(candidate.host ?? "")
      {
        return candidate
      }
    #endif
    return nil
  }
}
