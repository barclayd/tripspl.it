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
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var landscape = false
  /// Whether the bar runs down the side as the Duo's rail, which then carries the screen's actions.
  @State private var railed = false
  @State private var deleting: TripSnapshot?
  @State private var clearing: Attachment?
  var body: some View {
    @Bindable var model = model
    // The "+" tab is an action, not a destination: it starts a new trip, or on the Duo's rail adds to the open one.
    TabView(
      selection: Binding(
        get: { model.selectedTab },
        set: { tab in
          if tab != RootView.newTripTab {
            model.selectedTab = tab
          } else if addsToTrip, let trip = model.selectedTrip {
            model.editExpense(trip: trip, attachment: model.selectedAttachment ?? trip.currentAttachment)
          } else {
            model.showOnboarding = true
          }
        })
    ) {
      Tab("Trips", systemImage: "suitcase", value: 0) {
        NavigationSplitView(
          columnVisibility: Binding(
            get: { twoPane && model.fullScreenDay && model.selectedAttachment != nil ? .detailOnly : .all },
            set: { if twoPane && model.selectedAttachment != nil { model.fullScreenDay = $0 == .detailOnly } }),
          // Derived from the selection, so folding or unfolding the Duo lands on the same screen.
          preferredCompactColumn: Binding(
            get: { model.selectedTripID == nil ? .sidebar : .detail },
            set: {
              if $0 == .sidebar {
                model.selectedTripID = nil
                model.selectedAttachment = nil
              }
            })
        ) {
          let tripBeside = twoPane && model.selectedAttachment != nil
          ZStack {
            TripsView(compact: twoPane).opacity(tripBeside ? 0 : 1)
              .allowsHitTesting(!tripBeside).accessibilityHidden(tripBeside)
            if tripBeside, let trip = model.selectedTrip {
              TripDetailView(tripID: trip.id, compact: true)
            }
          }
          .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 360)
          .navigationTitle("")
          // Each pane draws its own header, so the bar only shows to hold the rail.
          .toolbar(railed ? .automatic : .hidden, for: .navigationBar)
          .toolbar {
            // Abroad on a trip under way, converting stays one tap from the trips list too.
            if railed && model.selectedTripID == nil && model.store.trips.contains(where: \.showsHomeConverter) {
              convertItem { model.showConverter = true }
            }
          }
        } detail: {
          NavigationStack {
            ZStack {
              Theme.background.ignoresSafeArea()
              if let trip = model.selectedTrip {
                TripDetailView(tripID: trip.id).opacity(model.selectedAttachment == nil ? 1 : 0)
                  .allowsHitTesting(model.selectedAttachment == nil).accessibilityHidden(
                    model.selectedAttachment != nil)
                  .id(trip.id)
                  .transition(
                    reduceMotion
                      ? .opacity
                      : .asymmetric(insertion: .offset(y: 28).combined(with: .opacity), removal: .opacity))
                if let attachment = model.selectedAttachment {
                  DayView(tripID: trip.id, attachment: attachment, showsPaneControls: twoPane)
                }
              } else {
                ContentUnavailableView(
                  "Select a trip", systemImage: "airplane")
              }
            }
            // Picking a trip in the sidebar slides it up into the pane beside.
            .animation(twoPane ? .smooth(duration: 0.5) : nil, value: model.selectedTripID)
            .pinsBar(twoPane)
            .navigationBarBackButtonHidden(true)
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                // In two panes the Day floats its own close, so Back only stays at the top of the rail.
                if twoPane ? railed && model.selectedAttachment != nil : model.selectedTripID != nil {
                  Button("Back", systemImage: "chevron.backward") {
                    if model.selectedAttachment != nil {
                      model.selectedAttachment = nil
                      model.fullScreenDay = false
                    } else {
                      model.selectedTripID = nil
                    }
                  }
                }
              }
              if let trip = model.selectedTrip {
                // On the rail, the "+" tab adds the expense instead.
                if !railed && model.selectedAttachment == nil {
                  ToolbarItem(placement: .primaryAction) {
                    Button("Add expense", systemImage: "plus") {
                      model.editExpense(trip: trip, attachment: trip.currentAttachment)
                    }
                  }
                }
                if let attachment = model.selectedAttachment {
                  if railed && trip.isAbroad(attachment) {
                    convertItem { model.showConverter = true }
                  }
                } else if !railed || trip.showsHomeConverter {
                  convertItem { model.showConverter = true }
                }
                if model.selectedAttachment == nil {
                  ToolbarItem {
                    Button("Share trip", systemImage: "square.and.arrow.up") {
                      model.showTripSettings = true
                    }
                  }
                }
                if #available(iOS 27.0, *) {
                  ToolbarOverflowMenu { more(trip) }
                } else {
                  ToolbarItem {
                    Menu("More", systemImage: "ellipsis") { more(trip) }
                  }
                }
              }
            }
            .confirmationDialog(
              "Delete \(deleting?.name ?? "this trip")?",
              isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
              titleVisibility: .visible, presenting: deleting
            ) { trip in
              Button("Delete trip", role: .destructive) { Task { await model.deleteTrip(trip) } }
            } message: { trip in
              Text(
                trip.travellers.count > 1
                  ? "Its days and expenses go for all \(trip.travellers.count) travellers. This can’t be undone."
                  : "Its days and expenses go too. This can’t be undone.")
            }
            .confirmationDialog(
              clearTitle,
              isPresented: Binding(get: { clearing != nil }, set: { if !$0 { clearing = nil } }),
              titleVisibility: .visible, presenting: clearing
            ) { attachment in
              Button("Delete expenses", role: .destructive) {
                if let trip = model.selectedTrip { model.clearDay(attachment, trip: trip) }
              }
            }
          }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        // Two panes only when unfolded on its side; otherwise one, capped in width.
        .environment(\.horizontalSizeClass, twoPane ? .regular : .compact)
      }
      Tab("Globe", systemImage: "globe", value: 1) { NavigationStack { GlobeView() } }
      Tab(addsToTrip ? addTitle : "New trip", systemImage: "plus", value: RootView.newTripTab, role: .search) {
        Color.clear
      }
    }
    .readVerticalRail($railed)
    .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { landscape = $0 }
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
      if let trip = model.selectedTrip ?? model.store.trips.first(where: \.showsHomeConverter) {
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
        // `--landscape` turns the device on its side, for the Duo's tent and two pane layouts.
        if ProcessInfo.processInfo.arguments.contains("--landscape"),
          let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        {
          try? await Task.sleep(for: .milliseconds(300))
          scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { error in
            print("Couldn’t turn to landscape: \(error.localizedDescription)")
          }
        }
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
          // `--confirm delete|clear` asks before deleting the trip or clearing the open day.
          if let index = arguments.firstIndex(of: "--confirm"), arguments.indices.contains(index + 1) {
            try? await Task.sleep(for: .seconds(1))
            if arguments[index + 1] == "delete" { deleting = trip } else { clearing = model.selectedAttachment }
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
extension RootView {
  /// Unfolded on its side: the Duo's two panes, or an iPad in landscape.
  private var twoPane: Bool { sizeClass == .regular && landscape }

  /// On the rail, "+" adds to the trip on screen rather than starting a new one.
  private var addsToTrip: Bool { railed && model.selectedTab == 0 && model.selectedTrip != nil }

  private var addTitle: String {
    model.selectedAttachment?.kind == .leg ? "Add travel" : "Add expense"
  }

  /// Quick convert, kept on the rail ahead of share and "…" while there's room.
  @ToolbarContentBuilder private func convertItem(_ action: @escaping () -> Void) -> some ToolbarContent {
    if #available(iOS 27.0, *) {
      ToolbarItem {
        Button("Quick convert", systemImage: "arrow.left.arrow.right", action: action)
      }.visibilityPriority(.high)
    } else {
      ToolbarItem {
        Button("Quick convert", systemImage: "arrow.left.arrow.right", action: action)
      }
    }
  }

  /// The "…" menu: trip actions, then the open day's, then account. Destructive ones confirm first.
  @ViewBuilder private func more(_ trip: TripSnapshot) -> some View {
    Button("Edit trip", systemImage: "pencil") { model.showTripSettings = true }
    if trip.role == "owner" {
      Button("Delete trip", systemImage: "trash", role: .destructive) { deleting = trip }
    }
    if let attachment = model.selectedAttachment {
      let items = trip.expenses(for: attachment)
      Section {
        if attachment.kind == .day {
          Menu("Move to another day", systemImage: "calendar") {
            ForEach(Array(trip.days.enumerated()), id: \.element.id) { index, day in
              if day.id != attachment.id {
                Button("Day \(index + 1) · \(CivilDate.display(day.date, format: "EEE d MMM"))") {
                  model.moveExpenses(items, to: .init(kind: .day, id: day.id), trip: trip)
                }
              }
            }
          }
          .disabled(items.isEmpty)
        }
        Button("Clear day", systemImage: "xmark.bin", role: .destructive) { clearing = attachment }
          .disabled(items.isEmpty)
      }
    }
    Section {
      Button("Account & sync", systemImage: "person.crop.circle") { model.showSettings = true }
    }
  }

  private var clearTitle: String {
    guard let trip = model.selectedTrip, let clearing else { return "Clear day?" }
    let count = trip.expenses(for: clearing).count
    return "Delete \(count == 1 ? "the expense" : "all \(count) expenses") on this day?"
  }
}
struct InviteLink: Identifiable {
  var url: URL
  var id: String { url.absoluteString }
}
