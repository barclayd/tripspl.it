import Foundation

public struct ServiceError: LocalizedError, Sendable {
  public init(
    code: String,
    message: String,
    status: Int = 0
  ) {
    self.code = code
    self.message = message
    self.status = status
  }
  public var code: String
  public var message: String
  public var status: Int = 0
  public var errorDescription: String? { message }
}
