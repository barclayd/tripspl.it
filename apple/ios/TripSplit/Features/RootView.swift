import SwiftUI
import TripSplitAccountUI
import TripSplitApplication
import TripSplitConversionUI
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitExpensesUI
import TripSplitGlobeUI
import TripSplitOnboardingUI
import TripSplitPersistence
import TripSplitSync
import TripSplitTripsUI

struct RootView: View {
  static let newTripTab = 2
  @Environment(AppModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase
  @State private var columns: NavigationSplitViewVisibility = .all
  @State private var preferredColumn: NavigationSplitViewColumn = .sidebar
  @State private var wide = false
  var body: some View {
    @Bindable var model = model
    // The "+" tab is an action, not a destination: selecting it starts a new trip in place.
    TabView(
      selection: Binding(
        get: { model.selectedTab },
        set: { tab in
          if tab == RootView.newTripTab {
            model.showOnboarding = true
          } else {
            model.selectedTab = tab
          }
        })
    ) {
      Tab("Trips", systemImage: "suitcase", value: 0) {
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $preferredColumn) {
          ZStack {
            TripsView(compact: wide).opacity(model.selectedAttachment == nil ? 1 : 0)
              .allowsHitTesting(model.selectedAttachment == nil).accessibilityHidden(
                model.selectedAttachment != nil)
            if let trip = model.selectedTrip, model.selectedAttachment != nil {
              TripDetailView(tripID: trip.id, compact: true)
            }
          }.navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 360).navigationTitle(
            model.selectedAttachment == nil ? "Trips" : model.selectedTrip?.name ?? "Trip"
          )
          // The phone's trips root draws its own large header.
          .toolbar(
            !wide && model.selectedAttachment == nil ? .hidden : .automatic, for: .navigationBar)
        } detail: {
          NavigationStack {
            ZStack {
              Theme.background.ignoresSafeArea()
              if let trip = model.selectedTrip {
                TripDetailView(tripID: trip.id).opacity(model.selectedAttachment == nil ? 1 : 0)
                  .allowsHitTesting(model.selectedAttachment == nil).accessibilityHidden(
                    model.selectedAttachment != nil)
                if let attachment = model.selectedAttachment {
                  DayView(tripID: trip.id, attachment: attachment, showsPaneControls: wide)
                }
              } else {
                ContentUnavailableView(
                  "Select a trip", systemImage: "airplane")
              }
            }
            .navigationBarBackButtonHidden(true)
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                if model.selectedTripID != nil {
                  Button("Back", systemImage: "chevron.backward") {
                    if model.selectedAttachment != nil {
                      model.selectedAttachment = nil
                    } else {
                      model.selectedTripID = nil
                      preferredColumn = .sidebar
                    }
                  }
                }
              }
              if let trip = model.selectedTrip {
                if model.selectedAttachment == nil {
                  ToolbarItem(placement: .primaryAction) {
                    Button("Add expense", systemImage: "plus") {
                      model.editExpense(
                        trip: trip, attachment: model.selectedAttachment ?? trip.currentAttachment)
                    }
                  }
                }
                if model.selectedAttachment == nil {
                  if #available(iOS 27.0, *) {
                    ToolbarItem {
                      Button("Quick convert", systemImage: "arrow.left.arrow.right") {
                        model.showConverter = true
                      }
                    }.visibilityPriority(.high)
                  } else {
                    ToolbarItem {
                      Button("Quick convert", systemImage: "arrow.left.arrow.right") {
                        model.showConverter = true
                      }
                    }
                  }
                }
                ToolbarItem {
                  Button("Share trip", systemImage: "square.and.arrow.up") {
                    model.showTripSettings = true
                  }
                }
                if #available(iOS 27.0, *) {
                  ToolbarOverflowMenu {
                    Button("Edit trip", systemImage: "pencil") { model.showTripSettings = true }
                    Button("Account & sync", systemImage: "person.crop.circle") {
                      model.showSettings = true
                    }
                  }
                } else {
                  ToolbarItem {
                    Menu("More", systemImage: "ellipsis") {
                      Button("Edit trip", systemImage: "pencil") { model.showTripSettings = true }
                      Button("Account & sync", systemImage: "person.crop.circle") {
                        model.showSettings = true
                      }
                    }
                  }
                }
              }
            }
          }
        }.navigationSplitViewStyle(.balanced)
          .onGeometryChange(for: Bool.self) {
            $0.size.width >= 700
          } action: {
            wide = $0
            columns =
              $0 && !model.fullScreenDay ? .all : model.selectedTripID == nil ? .all : .detailOnly
          }
          .onChange(of: model.selectedTripID) { _, value in
            if value != nil {
              preferredColumn = .detail
              if !wide { columns = .detailOnly }
            }
          }
          .onChange(of: model.fullScreenDay) { _, full in columns = full ? .detailOnly : .all }
      }
      Tab("Globe", systemImage: "globe", value: 1) { NavigationStack { GlobeView() } }
      Tab("New trip", systemImage: "plus", value: RootView.newTripTab, role: .search) {
        Color.clear
      }
    }
    // The globe sits in dark space, so the tab bar and its sheets go dark with it.
    .preferredColorScheme(model.selectedTab == 1 ? .dark : nil)
    .sheet(isPresented: $model.showSettings) { SettingsView().trailingSheet() }
    .sheet(isPresented: $model.showTripSettings) {
      if let trip = model.selectedTrip { TripSettingsView(tripID: trip.id).trailingSheet() }
    }
    .sheet(item: $model.expenseDraft, onDismiss: { model.expenseDraft = nil }) { _ in
      ExpenseEditor().trailingSheet()
    }
    .sheet(isPresented: $model.showConverter) {
      if let trip = model.selectedTrip {
        ConvertView(tripID: trip.id, attachment: model.selectedAttachment ?? trip.currentAttachment)
          .trailingSheet()
      }
    }
    .fullScreenCover(isPresented: $model.showOnboarding) { OnboardingView() }
    .sheet(
      item: Binding(
        get: { model.inviteURL.map(InviteLink.init) }, set: { model.inviteURL = $0?.url })
    ) { invite in AcceptInviteView(url: invite.url) }
    .toast(model.toast)
    .alert(
      "Couldn’t complete that",
      isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
    ) {
      Button("OK") { model.error = nil }
    } message: {
      Text(model.error ?? "")
    }
    .task {
      #if DEBUG
        // Opens a demo trip straight away so simulator screenshots can reach trip screens.
        if ProcessInfo.processInfo.arguments.contains("--open-trip") {
          let trips = model.store.trips
          model.selectedTripID = (trips.first { $0.phase == .now } ?? trips.first)?.id
        }
        let arguments = ProcessInfo.processInfo.arguments
        // `--globe` opens the globe tab; `--globe-trip` also picks out the trip under way.
        if arguments.contains("--globe") || arguments.contains("--globe-trip") {
          model.selectedTripID = nil
          model.selectedTab = 1
          if arguments.contains("--globe-trip") {
            // Picked once the globe is up, as a tap would, so the camera flies there.
            try? await Task.sleep(for: .seconds(2))
            let trips = model.store.trips
            model.globeTripID = (trips.first { $0.phase == .now } ?? trips.first)?.id
          }
        }
        // `--onboarding-step N` opens new trip onboarding at step N with a demo route filled in.
        if let index = arguments.firstIndex(of: "--onboarding-step"), arguments.indices.contains(index + 1),
          let step = Int(arguments[index + 1])
        {
          var draft = OnboardingDraft.newTrip()
          draft.stops = [("PT", 4), ("ES", 3), ("MA", 3)].compactMap { code, nights in
            Destination.country(code)?.stop(nights: nights)
          }
          draft.reconcileRoute()
          if step > 1 { draft.setDeparture(CivilDate.adding(12, to: draft.startsOn)) }
          if step >= 3 {
            draft.travellers += zip(["Sam", "Priya", "Jonah"], [250.0, 75, 160]).map {
              Traveller(name: $0, hue: $1)
            }
          }
          if step >= 5 { draft.budget = "3200" }
          draft.step = step
          model.onboarding = draft
          model.showOnboarding = true
        }
        if let trip = model.selectedTrip {
          // `--open-day current|outbound|return`, `--add-expense` and `--quick-convert` reach the day and sheets.
          if let index = arguments.firstIndex(of: "--open-day"), arguments.indices.contains(index + 1) {
            let kind: TravelLeg.Kind? =
              switch arguments[index + 1] {
              case "outbound": .outbound
              case "return": .return
              default: nil
              }
            let leg = kind.flatMap { kind in trip.legs.first { $0.kind == kind } }
            model.selectedAttachment = leg.map { .init(kind: .leg, id: $0.id) } ?? trip.currentAttachment
          }
          if arguments.contains("--add-expense") {
            model.editExpense(trip: trip, attachment: model.selectedAttachment ?? trip.currentAttachment)
          }
          if arguments.contains("--quick-convert") {
            model.showConverter = true
          }
        }
      #endif
      await model.sync.syncAll()
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        model.sync.startLive(tripID: model.selectedTripID)
        Task { await model.sync.syncAll() }
      }
      if phase == .background {
        model.sync.stopLive()
        model.persistDraft()
        model.saveOnboarding()
      }
    }
    .onChange(of: model.selectedTripID) { _, id in model.sync.startLive(tripID: id) }
    .onChange(of: model.sync.session?.user.id) { _, account in
      model.selectedTripID = nil
      model.selectedAttachment = nil
      if account != nil, let url = model.pendingInvitation {
        model.pendingInvitation = nil
        model.showSettings = false
        Task {
          try? await Task.sleep(for: .milliseconds(400))
          model.inviteURL = url
        }
      }
    }
    .onOpenURL { model.inviteURL = $0 }
  }
}
struct InviteLink: Identifiable {
  var url: URL
  var id: String { url.absoluteString }
}
