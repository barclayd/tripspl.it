import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitPersistence
import TripSplitSync

package struct SyncNotice: View {
  package init(tripID: String) {
    self.tripID = tripID
  }
  @Environment(AppModel.self) private var model
  package var tripID: String
  @State private var review = false
  package var body: some View {
    if let envelope = model.store.envelopes[tripID] {
      let problems = envelope.pending.filter { $0.problem != nil }.count
      if envelope.restoreReview || problems > 0 {
        Button {
          review = true
        } label: {
          Label(
            envelope.restoreReview
              ? "Restored changes need review" : "\(problems) changes need review",
            systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
          ).font(.footnote.weight(.bold)).foregroundStyle(Theme.bad).padding(14).frame(
            maxWidth: .infinity, alignment: .leading
          ).background(Theme.surface, in: RoundedRectangle(cornerRadius: 15))
        }.sheet(isPresented: $review) {
          NavigationStack {
            SyncReviewView(tripID: tripID).toolbar {
              ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") { review = false }
              }
            }
          }
        }
      } else if !envelope.pending.isEmpty || envelope.confirmed.syncEpoch == "local" {
        Label(
          model.sync.session == nil
            ? "Saved on this device" : "\(envelope.pending.count) changes waiting to sync",
          systemImage: model.sync.session == nil ? "iphone" : "icloud.and.arrow.up"
        ).font(.caption).foregroundStyle(Theme.secondary)
      }
    }
  }
}
package struct SyncReviewView: View {
  package init(tripID: String) {
    self.tripID = tripID
  }
  @Environment(AppModel.self) private var model
  package var tripID: String
  @State private var confirmReapply: String?
  package var body: some View {
    if let envelope = model.store.envelopes[tripID] {
      List {
        if let account = envelope.accountID, account != model.sync.session?.user.id {
          Section {
            Text(
              "This trip belongs to its original signed-in account. Sign in to that account to sync."
            )
          }
        }
        if envelope.restoreReview {
          Section("Restored data") {
            Text(
              "Review pending changes against the latest confirmed snapshot before uploading them.")
            Text(
              "Confirmed revision \(envelope.confirmed.revision) · \(envelope.pending.count) local changes"
            ).font(.caption)
            Button("Fetch latest server version") { Task { await model.sync.syncAll() } }
            Button("I’ve reviewed these changes") {
              model.perform {
                try model.sync.approveRestore(tripID)
                model.changed()
              }
            }.disabled(model.sync.session == nil)
          }
        }
        Section("Local changes") {
          if envelope.pending.isEmpty { Text("Everything is up to date.") }
          ForEach(envelope.pending) { pending in
            VStack(alignment: .leading, spacing: 10) {
              Text(title(pending.operation)).font(.headline)
              Text(
                pending.problem
                  ?? (pending.attempted
                    ? "Waiting for server acknowledgement. This exact operation will be retried."
                    : "Saved locally, waiting to upload.")
              ).font(.footnote).foregroundStyle(
                pending.problem == nil ? Theme.secondary : Theme.bad)
              if case .expense(let local) = pending.operation.payload {
                Text(
                  "Your draft: \(local.title) · \(Money.format(Money.minor(local.amountMinor) ?? 0, local.currency)) · \(local.status.rawValue)"
                ).font(.caption)
                if let server = envelope.confirmed.expenses.first(where: { $0.id == local.id }) {
                  Text(
                    "Server: \(server.title) · \(Money.format(Money.minor(server.amountMinor) ?? 0, server.currency)) · \(server.status.rawValue)"
                  ).font(.caption).foregroundStyle(Theme.secondary)
                }
              }
              if pending.problem != nil {
                HStack {
                  Button("Keep server version") {
                    model.perform { try model.store.discard(pending.id, tripID: tripID) }
                  }.buttonStyle(.bordered)
                  Button("Apply my draft") { confirmReapply = pending.id }.buttonStyle(
                    .borderedProminent)
                }
              }
            }.padding(.vertical, 6)
          }
        }
      }.navigationTitle("Sync review").confirmationDialog(
        "Apply this draft over the current server version?",
        isPresented: Binding(
          get: { confirmReapply != nil }, set: { if !$0 { confirmReapply = nil } }),
        titleVisibility: .visible
      ) {
        Button("Apply my reviewed draft") {
          if let id = confirmReapply {
            model.perform {
              try model.sync.resolveByReapplying(id, tripID: tripID)
              model.changed()
            }
          }
          confirmReapply = nil
        }
      }
    }
  }
  private func title(_ op: TripSplitDomain.Operation) -> String {
    switch op.payload {
    case .expense(let e): e.title
    case .repayment: model.store.trip(tripID)?.hasCompanions == true ? "Repayment" : "Payment"
    case .traveller(let t): t.name
    case .settings: "Trip settings"
    case .reschedule: "New dates"
    case .dayLocation: "Day location"
    case .archive: "Trip archive"
    case .none: "Delete item"
    }
  }
}
