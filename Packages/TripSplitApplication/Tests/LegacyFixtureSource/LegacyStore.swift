import Foundation
import SwiftData

@Model final class LocalDocument {
  @Attribute(.unique) var id: String
  var data: Data
  init(id: String, data: Data) {
    self.id = id
    self.data = data
  }
}

@main struct LegacyFixture {
  @MainActor static func main() throws {
    let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let documents = try JSONDecoder().decode(
      [String: Data].self, from: Data(contentsOf: directory.appending(path: "documents.json")))
    let config = ModelConfiguration(
      url: directory.appending(path: "legacy.store"), cloudKitDatabase: .none)
    let container = try ModelContainer(for: LocalDocument.self, configurations: config)
    let context = ModelContext(container)
    context.autosaveEnabled = false
    for (id, data) in documents { context.insert(LocalDocument(id: id, data: data)) }
    try context.save()
    let stored = try context.fetch(FetchDescriptor<LocalDocument>())
    precondition(stored.count == documents.count)
    for doc in stored { precondition(doc.data == documents[doc.id]) }
    print("Old TripSplit module wrote and verified \(stored.count) exact documents")
  }
}
