import Foundation
import TripSplitDomain

struct ErrorEnvelope: Decodable {
  struct Detail: Decodable {
    var code: String
    var message: String
  }
  var error: Detail
}
public struct EmptyBody: Codable, Sendable { public init() {} }
public struct APIClient: Sendable {
  public let baseURL: URL?
  public let transport: URLSession
  public init(baseURL: URL? = nil, transport: URLSession = .shared) {
    self.transport = transport
    self.baseURL = baseURL
  }
  public func request<Response: Decodable & Sendable, Body: Encodable & Sendable>(
    _ path: String, method: String = "GET", body: Body? = Optional<EmptyBody>.none,
    token: String? = nil
  ) async throws -> Response {
    guard let baseURL else {
      throw ServiceError(
        code: "not_configured",
        message: "Cloud sync isn’t configured in this build. Your trips are saved on this device.")
    }
    guard
      let endpoint = URL(
        string: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
          + "/v1" + path)
    else { throw URLError(.badURL) }
    var request = URLRequest(url: endpoint)
    request.httpMethod = method
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let body { request.httpBody = try JSONEncoder().encode(body) }
    let (data, response) = try await transport.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    guard (200..<300).contains(response.statusCode) else {
      let server = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
      throw ServiceError(
        code: server?.error.code ?? "http_\(response.statusCode)",
        message: server?.error.message
          ?? "The server couldn’t complete this request (\(response.statusCode)).",
        status: response.statusCode)
    }
    return try JSONDecoder().decode(Response.self, from: data)
  }
  public func quote(from: String, to: String, date: String, token: String?) async throws -> FXQuote
  {
    guard let baseURL else {
      throw ServiceError(
        code: "not_configured",
        message:
          "Live rates need a configured cloud service. You can enter the actual home-currency charge instead."
      )
    }
    var components = URLComponents(
      url: baseURL.appending(path: "v1/fx"), resolvingAgainstBaseURL: false)!
    components.queryItems = [
      URLQueryItem(name: "from", value: from), .init(name: "to", value: to),
      .init(name: "date", value: date),
    ]
    var request = URLRequest(url: components.url!)
    request.timeoutInterval = 8
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    let (data, response) = try await transport.data(for: request)
    guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
      throw ServiceError(
        code: "fx_unavailable",
        message:
          "No reference rate is available. Enter the actual charge, or save this expense with conversion pending."
      )
    }
    return try JSONDecoder().decode(FXQuote.self, from: data)
  }
}
