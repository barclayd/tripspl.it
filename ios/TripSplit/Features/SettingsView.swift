import AuthenticationServices
import SwiftUI

struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var deleting = false
  @State private var busy = false
  @State private var message: String?
  var body: some View {
    NavigationStack {
      Form {
        Section {
          Label("Your trips, together", systemImage: "person.2.fill").font(.headline)
          Text(
            "Everything saves on this device first. Sign in to share trips and keep changes in sync."
          ).font(.subheadline).foregroundStyle(.secondary)
          if let session = model.sync.session {
            LabeledContent("Signed in", value: session.user.displayName)
            Button("Sync now", systemImage: "arrow.triangle.2.circlepath") {
              Task { await model.sync.syncAll() }
            }.disabled(model.sync.isSyncing)
            if let date = model.sync.lastSynced {
              Text("Last synced \(date.formatted(date: .omitted, time: .shortened))").font(.caption)
            }
            Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") {
              run { try await model.sync.signOut() }
            }
            Text(
              "Signing out keeps local trips and pending changes bound to this account. They won’t upload into another account."
            ).font(.caption).foregroundStyle(.secondary)
          } else if model.sync.configured {
            if model.sync.challenge != nil {
              SignInWithAppleButton(.signIn) {
                model.sync.configure($0)
              } onCompletion: { result in
                Task { await model.sync.completeApple(result) }
              }.frame(height: 48).signInWithAppleButtonStyle(.black)
            } else {
              Button("Prepare Apple sign-in", systemImage: "person.crop.circle") {
                Task { await model.sync.prepareApple() }
              }
            }
          } else {
            Label("Cloud service not configured", systemImage: "icloud.slash")
            Text(
              "This build is ready for local use. Cloud sharing and live rates need the project’s HTTPS service URL and Apple sign-in configuration."
            ).font(.footnote).foregroundStyle(.secondary)
          }
          if let error = model.sync.message {
            Text(error).font(.footnote).foregroundStyle(Theme.bad)
          }
        }
        Section("Local data & recovery") {
          Text(
            "Normal device backups can include your saved trips, drafts and unsent changes. A replacement device requires Apple sign-in again; restored changes are reviewed before syncing."
          ).font(.footnote)
          ForEach(model.store.trips) { trip in
            NavigationLink(trip.name) { SyncReviewView(tripID: trip.id) }
          }
        }
        if !model.store.archivedTrips.isEmpty {
          Section("Archived trips") {
            ForEach(model.store.archivedTrips) { trip in
              HStack {
                Text(trip.name)
                Spacer()
                Button("Restore", systemImage: "arrow.uturn.backward") {
                  model.perform {
                    try model.store.enqueue(
                      .init(
                        syncEpoch: trip.syncEpoch, type: "trip.archive", entityId: trip.id,
                        expectedRevision: model.store.envelopes[trip.id]?.confirmed.revision
                          ?? trip.revision, payload: .archive(false)), tripID: trip.id)
                    model.changed()
                  }
                }.disabled(trip.role != "owner")
              }
            }
          }
        }
        if model.sync.session != nil {
          Section("Account") {
            Button(
              "Delete my account", systemImage: "person.crop.circle.badge.minus", role: .destructive
            ) { deleting = true }
            Text(
              "Shared trips remain for other members with your identity anonymised. Trips without other linked members are removed."
            ).font(.caption)
          }
        }
        if model.sync.deletionRequested {
          Section {
            Text(
              "Account deletion requested. The server is completing cleanup and Apple access revocation."
            ).foregroundStyle(Theme.good)
          }
        }
        if let message { Section { Text(message).foregroundStyle(Theme.bad) } }
        Section {
          LabeledContent("Version", value: "1.0")
          Text("TripSplit does not move money. Repayments record transfers you make elsewhere.")
            .font(.caption)
        }
      }.navigationTitle("Account & sync").toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close", systemImage: "xmark") { dismiss() }
        }
      }.disabled(busy)
        .confirmationDialog(
          "Delete your TripSplit account?", isPresented: $deleting, titleVisibility: .visible
        ) {
          Button("Delete account and personal data", role: .destructive) {
            run { try await model.sync.deleteAccount() }
          }
        } message: {
          Text(
            "This permanently removes your account, revokes access, and clears account-bound data from this device once accepted. Unsynced changes in these trips will also be removed."
          )
        }
        .task {
          if model.sync.configured && model.sync.session == nil { await model.sync.prepareApple() }
        }
    }
  }
  private func run(_ action: @escaping @MainActor () async throws -> Void) {
    busy = true
    Task {
      defer { busy = false }
      do { try await action() } catch { message = error.localizedDescription }
    }
  }
}
struct SyncNotice: View {
  @Environment(AppModel.self) private var model
  var tripID: String
  @State private var review = false
  var body: some View {
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
struct SyncReviewView: View {
  @Environment(AppModel.self) private var model
  var tripID: String
  @State private var confirmReapply: String?
  var body: some View {
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
  private func title(_ op: Operation) -> String {
    switch op.payload {
    case .expense(let e): e.title
    case .repayment: "Repayment"
    case .traveller(let t): t.name
    case .settings: "Trip settings"
    case .archive: "Trip archive"
    case .none: "Delete item"
    }
  }
}
struct TripSettingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var tripID: String
  @State private var name = ""
  @State private var budget = ""
  @State private var timeZone = TimeZone.current.identifier
  @State private var invite: Invite?
  @State private var message: String?
  @State private var archive = false
  @State private var busy = false
  @State private var newPerson = ""
  var body: some View {
    if let trip = model.store.trip(tripID) {
      NavigationStack {
        Form {
          Section("The trip") {
            TextField("Name", text: $name)
            HStack {
              Text(trip.homeCurrency)
              TextField("Whole-trip budget", text: $budget).keyboardType(.decimalPad)
            }
            Picker("Trip time zone", selection: $timeZone) {
              ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) {
                Text($0.replacingOccurrences(of: "_", with: " ")).tag($0)
              }
            }
            Text(
              "Today follows this time zone. The itinerary and home currency stay fixed once created, so existing financial records keep their dates and meaning."
            ).font(.footnote).foregroundStyle(.secondary)
          }.disabled(trip.role != "owner")
          Section("Travellers") {
            ForEach(trip.activeTravellers) { person in
              HStack {
                Avatar(traveller: person)
                Text(person.name)
                Spacer()
                if trip.role == "owner" && person.id != trip.ownerTravellerId {
                  Menu("Traveller actions", systemImage: "ellipsis.circle") {
                    Button("Invite to this traveller", systemImage: "square.and.arrow.up") {
                      createInvite(person.id)
                    }
                    Button("Archive traveller", systemImage: "person.crop.circle.badge.minus") {
                      model.perform {
                        var value = person
                        value.archived = true
                        try model.store.enqueue(
                          .init(
                            syncEpoch: trip.syncEpoch, type: "traveller.upsert",
                            entityId: person.id, expectedRevision: person.revision,
                            payload: .traveller(value)), tripID: trip.id)
                        model.changed()
                      }
                    }
                  }
                }
              }
            }
            if trip.role == "owner" {
              HStack {
                TextField("Add traveller", text: $newPerson)
                Button("Add", systemImage: "plus") {
                  model.perform {
                    let traveller = Traveller(
                      name: newPerson.trimmingCharacters(in: .whitespaces),
                      hue: Double((trip.travellers.count * 75) % 360))
                    try model.store.enqueue(
                      .init(
                        syncEpoch: trip.syncEpoch, type: "traveller.upsert", entityId: traveller.id,
                        expectedRevision: nil, payload: .traveller(traveller)), tripID: trip.id)
                    newPerson = ""
                    model.changed()
                  }
                }.disabled(
                  newPerson.trimmingCharacters(in: .whitespaces).isEmpty
                    || trip.activeTravellers.count >= 8)
              }
            }
          }
          if let invite {
            Section("Invitation") {
              Text(
                "This one-use invitation links an Apple account to the selected traveller. Expires \(invite.expiresAt)."
              ).font(.footnote)
              ShareLink(
                item: invite.url
                  ?? "tripsplit://invite/\(tripID)/\(invite.id)#token=\(invite.token)"
              ) { Label("Share invitation", systemImage: "square.and.arrow.up") }
              Button("Revoke invitation", systemImage: "xmark.circle", role: .destructive) {
                Task {
                  do {
                    struct OK: Decodable, Sendable { var ok: Bool }
                    let token = try await model.sync.accessToken()
                    let _: OK = try await model.sync.api.request(
                      "/trips/\(tripID)/invites/\(invite.id)", method: "DELETE", token: token)
                    self.invite = nil
                  } catch { message = error.localizedDescription }
                }
              }
            }
          }
          Section {
            NavigationLink("Review sync & local changes") { SyncReviewView(tripID: tripID) }
            if trip.role == "owner" {
              Button("Archive trip", systemImage: "archivebox", role: .destructive) {
                archive = true
              }
            }
          }
          if let message { Section { Text(message).foregroundStyle(Theme.bad) } }
        }.navigationTitle("Trip settings").toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Close", systemImage: "xmark") { dismiss() }
          }
          ToolbarItem(placement: .confirmationAction) {
            if trip.role == "owner" {
              Button("Save", systemImage: "checkmark") {
                model.perform {
                  var settings = TripSettings(trip)
                  settings.name = name
                  settings.timeZone = timeZone
                  settings.budgetMinor = String(
                    try Money.parse(budget, currency: trip.homeCurrency))
                  try model.store.enqueue(
                    .init(
                      syncEpoch: trip.syncEpoch, type: "trip.update", entityId: trip.id,
                      expectedRevision: model.store.envelopes[trip.id]?.confirmed.revision
                        ?? trip.revision, payload: .settings(settings)), tripID: trip.id)
                  model.changed()
                  dismiss()
                }
              }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
          }
        }
        .onAppear {
          name = trip.name
          timeZone = trip.timeZone
          budget = Money.input(Money.minor(trip.budgetMinor) ?? 0, currency: trip.homeCurrency)
        }
        .confirmationDialog("Archive \(trip.name)?", isPresented: $archive) {
          Button("Archive trip", role: .destructive) {
            model.perform {
              try model.store.enqueue(
                .init(
                  syncEpoch: trip.syncEpoch, type: "trip.archive", entityId: trip.id,
                  expectedRevision: model.store.envelopes[trip.id]?.confirmed.revision
                    ?? trip.revision, payload: .archive(true)), tripID: trip.id)
              model.selectedTripID = nil
              model.changed()
              dismiss()
            }
          }
        }
        .disabled(busy)
      }
    }
  }
  private func createInvite(_ travellerID: String) {
    busy = true
    Task {
      defer { busy = false }
      await model.sync.syncAll()
      do {
        invite = try await model.sync.createInvite(tripID: tripID, travellerID: travellerID)
      } catch { message = error.localizedDescription }
    }
  }
}
struct RepaymentView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var tripID: String
  var settlement: Settlement
  @State private var amount = ""
  @State private var note = ""
  var body: some View {
    if let trip = model.store.trip(tripID) {
      NavigationStack {
        Form {
          Section {
            Text("Record money that was already transferred outside TripSplit.").font(.subheadline)
            TextField("Amount in \(trip.homeCurrency)", text: $amount).keyboardType(.decimalPad)
            TextField("Note (optional)", text: $note)
          }
          Section {
            Text("This reduces the balance without adding to your trip’s cost.").font(.footnote)
          }
        }.navigationTitle("Record repayment").toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", systemImage: "xmark") { dismiss() }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save repayment", systemImage: "checkmark") {
              model.perform {
                let minor = try Money.parse(amount, currency: trip.homeCurrency)
                guard minor > 0 else { throw MoneyError.invalid }
                let value = Repayment(
                  fromTravellerId: settlement.from, toTravellerId: settlement.to,
                  amountMinor: String(minor), currency: trip.homeCurrency, paidOn: trip.today,
                  note: note)
                try model.store.enqueue(
                  .init(
                    syncEpoch: trip.syncEpoch, type: "repayment.upsert", entityId: value.id,
                    expectedRevision: nil, payload: .repayment(value)), tripID: trip.id)
                model.changed()
                dismiss()
              }
            }
          }
        }.onAppear { amount = Money.input(settlement.amount, currency: trip.homeCurrency) }
      }
    }
  }
}
struct AcceptInviteView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var url: URL
  @State private var message: String?
  @State private var busy = false
  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 24) {
        Text("You’re invited.").font(.system(size: 36, weight: .heavy, design: .default))
        Text(
          "Join a trip as the traveller chosen by its organiser. Sign in with Apple first, then accept the invitation."
        ).foregroundStyle(Theme.secondary)
        if model.sync.session == nil {
          Button("Sign in with Apple", systemImage: "person.crop.circle") {
            model.pendingInvitation = url
            dismiss()
            Task {
              try? await Task.sleep(for: .milliseconds(350))
              model.showSettings = true
            }
          }
        } else {
          PrimaryButton(title: "Accept invitation", symbol: "person.badge.plus") { accept() }
            .disabled(busy)
        }
        if let message { Text(message).font(.footnote).foregroundStyle(Theme.bad) }
        Spacer()
      }.pagePadding().background(Theme.background).toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close", systemImage: "xmark") { dismiss() }
        }
      }
    }
  }
  private func accept() {
    let path = url.pathComponents.filter { $0 != "/" }
    let parts = url.scheme == "tripsplit" ? path : Array(path.dropFirst())
    let fragment = URLComponents(string: "https://placeholder.invalid/?" + (url.fragment ?? ""))
    guard parts.count == 2,
      let secret = fragment?.queryItems?.first(where: { $0.name == "token" })?.value
    else {
      message = "This invitation link isn’t complete."
      return
    }
    busy = true
    Task {
      defer { busy = false }
      do {
        let trip = try await model.sync.acceptInvite(
          tripID: parts[0], inviteID: parts[1], token: secret)
        model.open(trip)
        dismiss()
      } catch { message = error.localizedDescription }
    }
  }
}
