import AuthenticationServices
import SwiftUI
import TripSplitAppleAdapters
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitNetworking
import TripSplitPersistence
import TripSplitSharedUI
import TripSplitSync

public struct SettingsView: View {
  public init() {
  }
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var deleting = false
  @State private var busy = false
  @State private var message: String?
  public var body: some View {
    NavigationStack {
      Form {
        Section {
          Label("Trip sharing", systemImage: "person.2.fill").font(.headline)
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
                AppleSignIn.configure($0, challenge: model.sync.challenge)
              } onCompletion: { result in
                Task { await AppleSignIn.complete(result, sync: model.sync) }
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
        WatchFaceSection()
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
          NavigationLink("Place data & acknowledgements") {
            ScrollView {
              Text(DestinationData.acknowledgements).font(.footnote).textSelection(.enabled)
                .padding()
            }.navigationTitle("Place data").navigationBarTitleDisplayMode(.inline)
          }
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
public struct TripSettingsView: View {
  public init(tripID: String) {
    self.tripID = tripID
  }
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var tripID: String
  @State private var name = ""
  @State private var budget = ""
  @State private var timeZone = TimeZone.current.identifier
  @State private var stops: [Stop] = []
  @State private var timeZoneSelection: DestinationTimeZoneSelection?
  @State private var loaded = false
  @State private var invite: Invite?
  @State private var message: String?
  @State private var archive = false
  @State private var busy = false
  @State private var newPerson = ""
  public var body: some View {
    if let trip = model.store.trip(tripID) {
      NavigationStack {
        Form {
          Section("The trip") {
            TextField("Name", text: $name)
            HStack {
              Text(trip.homeCurrency)
              TextField("Whole-trip budget", text: $budget).keyboardType(.decimalPad)
            }
            Text(
              "Itinerary dates and home currency stay fixed after creation."
            ).font(.footnote).foregroundStyle(.secondary)
          }.disabled(trip.role != "owner")
          Section("Destination time zones") {
            ForEach(stops) { stop in
              Button {
                timeZoneSelection = .init(id: stop.id)
              } label: {
                DestinationTimeZoneRow(
                  place: stop.place, identifier: stop.resolvedTimeZone,
                  date: CivilDate.date(
                    trip.days.first(where: { $0.stopId == stop.id })?.date ?? trip.startsOn))
              }.buttonStyle(.plain).accessibilityIdentifier("settings.timezone.\(stop.id)")
            }
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
                      hue: AvatarPalette.hue(at: trip.travellers.count))
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
                  settings.stops = stops
                  settings.timeZone = stops.first?.resolvedTimeZone ?? timeZone
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
          guard !loaded else { return }
          loaded = true
          name = trip.name
          timeZone = trip.timeZone
          stops = trip.stops
          budget = Money.input(Money.minor(trip.budgetMinor) ?? 0, currency: trip.homeCurrency)
        }
        .sheet(item: $timeZoneSelection) { selection in
          if let stop = stops.first(where: { $0.id == selection.id }) {
            TimeZonePicker(
              selection: timeZoneBinding(for: stop.id),
              allowedIdentifiers: DestinationTimeZones.identifiers(countryCode: stop.countryCode),
              title: stop.place,
              referenceDate: CivilDate.date(
                trip.days.first(where: { $0.stopId == stop.id })?.date ?? trip.startsOn))
          }
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
  private func timeZoneBinding(for stopID: String) -> Binding<String> {
    Binding(
      get: { stops.first(where: { $0.id == stopID })?.resolvedTimeZone ?? "" },
      set: { zone in
        guard let index = stops.firstIndex(where: { $0.id == stopID }) else { return }
        stops[index].timeZone = zone
        if index == 0 { timeZone = zone }
      })
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
public struct AcceptInviteView: View {
  public init(url: URL) {
    self.url = url
  }
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var url: URL
  @State private var message: String?
  @State private var busy = false
  public var body: some View {
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
