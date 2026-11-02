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
  /// Where the fold runs while the Duo's half open.
  @State private var fold: CGRect?
  /// How far down each pane's content starts, so the sidebar can start level with the pane beside.
  @State private var sidebarTop: CGFloat = 0
  @State private var detailTop: CGFloat = 0
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
          // Opening a day moves the whole path along a step: the trip slides over from the pane
          // beside as the day pushes in there, and the trips list steps aside, as a push would.
          ZStack {
            TripsView(compact: twoPane)
              .visualEffect { [tripBeside] content, proxy in
                content.offset(x: tripBeside ? -proxy.size.width * 0.3 : 0)
              }
              .opacity(tripBeside ? 0 : 1)
              .allowsHitTesting(!tripBeside).accessibilityHidden(tripBeside)
            if tripBeside, let trip = model.selectedTrip {
              TripDetailView(tripID: trip.id, compact: true)
                .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                // Stays over the trips list while it slides back out, not under it.
                .zIndex(1)
            }
          }
          .animation(reduceMotion ? .smooth(duration: 0.25) : .smooth(duration: 0.45), value: tripBeside)
          // Slides stay within the column, while backgrounds still run under the bars.
          .clipShape(ColumnClip(sides: twoPane))
          // Half open, the leading pane runs right up to the fold.
          .navigationSplitViewColumnWidth(
            min: bookFold?.minX ?? 300, ideal: bookFold?.minX ?? 340, max: bookFold?.minX ?? 360)
          .navigationTitle("")
          // Each pane draws its own header, so the bar only shows to hold the rail.
          .toolbar(railed ? .automatic : .hidden, for: .navigationBar)
          .toolbar {
            // Abroad on a trip under way, converting stays one tap from the trips list too.
            if railed && model.selectedTripID == nil && model.store.trips.contains(where: \.showsHomeConverter) {
              convertItem { model.showConverter = true }
            }
          }
          // Only takes effect on the sidebar column's content, not on the split view itself.
          .toolbar(removing: .sidebarToggle)
          // On the rail the sidebar gets no top inset while the pane beside keeps the rail's, so
          // both panes start on the same line, level with the time.
          .safeAreaPadding(.top, twoPane && railed ? max(0, detailTop - sidebarTop) : 0)
          .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { sidebarTop = $0 }
        } detail: {
          NavigationStack(
            path: Binding(
              get: { model.selectedAttachment == nil ? [] : [DayRoute.day] },
              set: { path in
                if path.isEmpty {
                  model.selectedAttachment = nil
                  model.fullScreenDay = false
                }
              })
          ) {
            ZStack {
              Theme.background.ignoresSafeArea()
              if let trip = model.selectedTrip {
                TripDetailView(tripID: trip.id)
                  .id(trip.id)
                  .transition(
                    reduceMotion
                      ? .opacity
                      : .asymmetric(insertion: .offset(y: 28).combined(with: .opacity), removal: .opacity))
              } else {
                ContentUnavailableView(
                  "Select a trip", systemImage: "airplane")
              }
            }
            // The pane beside starts past the fold, so nothing to tap sits in the curve.
            .safeAreaPadding(.leading, sidebarShown ? bookFold?.width ?? 0 : 0)
            // Picking a trip in the sidebar slides it up into the pane beside.
            .animation(twoPane ? .smooth(duration: 0.5) : nil, value: model.selectedTripID)
            .pinsBar(twoPane)
            // With no trip picked the pane has no items, so its bar would drop away and take the
            // sidebar's matching inset with it. Keeping it up holds the trips title on one line.
            .toolbar(twoPane && railed ? .visible : .automatic, for: .navigationBar)
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { detailTop = $0 }
            .toolbar {
              if let trip = model.selectedTrip {
                // On the rail, the "+" tab adds the expense instead.
                if !railed {
                  ToolbarItem(placement: .primaryAction) {
                    Button("Add expense", systemImage: "plus") {
                      model.editExpense(trip: trip, attachment: trip.currentAttachment)
                    }
                  }
                }
                if !railed || trip.showsHomeConverter {
                  convertItem { model.showConverter = true }
                }
                ToolbarItem {
                  Button("Share trip", systemImage: "square.and.arrow.up") {
                    model.showTripSettings = true
                  }
                }
                moreItem(trip, day: nil)
              }
            }
            .navigationDestination(for: DayRoute.self) { _ in
              if let trip = model.selectedTrip {
                OpenDay { attachment in
                  ZStack {
                    Theme.background.ignoresSafeArea()
                    DayView(tripID: trip.id, attachment: attachment, showsPaneControls: twoPane)
                      .id(attachment)
                      .transition(.opacity)
                  }
                  // Picking another day beside swaps this one in place rather than pushing again.
                  .animation(.smooth(duration: 0.25), value: attachment)
                  .safeAreaPadding(.leading, sidebarShown ? bookFold?.width ?? 0 : 0)
                  .pinsBar(twoPane)
                  // Half of an iPad's two panes, the day floats its own Close instead.
                  .navigationBarBackButtonHidden(twoPane && !railed)
                  .toolbar {
                    if railed && trip.isAbroad(attachment) {
                      convertItem { model.showConverter = true }
                    }
                    moreItem(trip, day: attachment)
                  }
                }
              }
            }
          }
          // Asked from either page, so they're kept on the stack itself.
          .confirmsDeleting($deleting)
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
        .navigationSplitViewStyle(.balanced)
        .readFold($fold)
        .animation(.smooth, value: bookFold)
        // Two panes only when unfolded on its side; otherwise one, capped in width.
        .environment(\.horizontalSizeClass, twoPane ? .regular : .compact)
      }
      Tab("Globe", systemImage: "globe", value: 1) { NavigationStack { GlobeView() } }
      // The rail shows no titles, so only VoiceOver hears what it adds. Retitling the tab as the
      // rail turned back into the bar kept the old label widths, cutting "Trips" to "T…".
      Tab("New trip", systemImage: "plus", value: RootView.newTripTab, role: .search) { Color.clear }
        .accessibilityLabel(addTitle, isEnabled: addsToTrip)
    }
    .readVerticalRail($railed)
    // Upright on the inner screen the bars run across it but don't fade what scrolls beneath, as
    // they do on iPhone, so content showed sharp behind them.
    .scrollEdgeEffectStyle(unfolded && !landscape ? .soft : nil, for: .vertical)
    .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { landscape = $0 }
    // The globe sits in dark space, so the tab bar and its sheets go dark with it.
    .preferredColorScheme(model.selectedTab == 1 ? .dark : nil)
    .sheet(isPresented: $model.showSettings) { SettingsView().trailingSheet(open: unfolded) }
    .sheet(isPresented: $model.showTripSettings) {
      if let trip = model.selectedTrip { TripSettingsView(tripID: trip.id).trailingSheet(open: unfolded) }
    }
    .sheet(item: $model.expenseDraft, onDismiss: { model.expenseDraft = nil }) { _ in
      ExpenseEditor().trailingSheet(open: unfolded)
    }
    .sheet(isPresented: $model.showConverter) {
      if let trip = model.selectedTrip ?? model.store.trips.first(where: \.showsHomeConverter) {
        ConvertView(
          tripID: trip.id, attachment: model.selectedAttachment ?? trip.currentAttachment, tent: tent
        )
        .trailingSheet(open: unfolded)
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
        // `--landscape` turns the device on its side, for the Duo's tent and two pane layouts.
        if ProcessInfo.processInfo.arguments.contains("--landscape"),
          let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        {
          try? await Task.sleep(for: .milliseconds(300))
          scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { error in
            print("Couldn’t turn to landscape: \(error.localizedDescription)")
          }
        }
        // `--open-trip` opens a demo trip straight away so simulator screenshots can reach trip screens.
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
          draft.step = step
          if draft.reached(1), let home = Destination.home(region: Locale.current.region?.identifier) {
            draft.setOrigin(home.origin)
          }
          // Step 1 opens on a bare calendar; the steps after it have dates picked.
          if draft.reached(2) {
            let leaving = CivilDate.adding(12, to: draft.startsOn)
            draft.pick(leaving)
            draft.pick(CivilDate.adding(draft.nights, to: leaving))
          }
          if draft.reached(3) {
            draft.travellers += zip(["Sam", "Priya", "Jonah"], [250.0, 75, 160]).map {
              Traveller(name: $0, hue: $1)
            }
          }
          if draft.reached(5) { draft.budget = "3200" }
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
            // `--expense-amount 6.40` types an amount, to show the conversion and the split.
            if let index = arguments.firstIndex(of: "--expense-amount"), arguments.indices.contains(index + 1) {
              model.expenseDraft?.amount = arguments[index + 1]
            }
          }
          if arguments.contains("--quick-convert") {
            model.showConverter = true
          }
          // `--confirm delete|clear` asks before deleting the trip or clearing the open day.
          if let index = arguments.firstIndex(of: "--confirm"), arguments.indices.contains(index + 1) {
            try? await Task.sleep(for: .seconds(1))
            if arguments[index + 1] == "delete" { deleting = trip } else { clearing = model.selectedAttachment }
          }
          // `--walk-days` opens a late day, moves to an earlier one, then closes it, to film the transitions.
          if arguments.contains("--walk-days") {
            for day in [trip.days.dropLast().last, trip.days.dropLast(4).last].compactMap(\.self) {
              try? await Task.sleep(for: .seconds(2.5))
              model.openDay(.init(kind: .day, id: day.id))
            }
            try? await Task.sleep(for: .seconds(2.5))
            model.selectedAttachment = nil
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
  /// The Duo's inner display, or an iPad.
  private var unfolded: Bool { sizeClass == .regular }

  /// Unfolded on its side: the Duo's two panes, or an iPad in landscape.
  private var twoPane: Bool { unfolded && landscape }

  /// Folded on its side and stood on a counter (or a phone on its side): read from arm's length.
  private var tent: Bool { sizeClass == .compact && landscape }

  /// Both panes showing, rather than a Day full screen.
  private var sidebarShown: Bool { twoPane && !(model.fullScreenDay && model.selectedAttachment != nil) }

  /// Half open like a book, the fold runs down between the panes and becomes the divider.
  private var bookFold: CGRect? {
    guard twoPane, let fold, fold.height > fold.width else { return nil }
    return fold
  }

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

  /// The system "…" overflow on iOS 27, holding whatever the rail has no room for.
  @ToolbarContentBuilder private func moreItem(_ trip: TripSnapshot, day: Attachment?) -> some ToolbarContent {
    if #available(iOS 27.0, *) {
      ToolbarOverflowMenu { more(trip, day: day) }
    } else {
      ToolbarItem {
        Menu("More", systemImage: "ellipsis") { more(trip, day: day) }
      }
    }
  }

  /// The "…" menu: trip actions, then the open day's, then account. Destructive ones confirm first.
  @ViewBuilder private func more(_ trip: TripSnapshot, day: Attachment?) -> some View {
    Button("Edit trip", systemImage: "pencil") { model.showTripSettings = true }
    if trip.role == "owner" {
      Button("Delete trip", systemImage: "trash", role: .destructive) { deleting = trip }
    }
    if let attachment = day {
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
/// The one page pushed over a trip: its open day or travel leg.
private enum DayRoute: Hashable { case day }

/// The open day, kept on screen as it slides away after the selection clears.
private struct OpenDay<Content: View>: View {
  @Environment(AppModel.self) private var model
  @State private var last: Attachment?
  @ViewBuilder var content: (Attachment) -> Content

  var body: some View {
    Group {
      if let attachment = model.selectedAttachment ?? last { content(attachment) }
    }
    .onChange(of: model.selectedAttachment, initial: true) { _, open in
      if let open { last = open }
    }
  }
}

/// Clips a column's sides only, so what slides across stays in it while backgrounds still run
/// up under the status bar and down under the tab bar. A lone column isn't clipped at all.
private struct ColumnClip: Shape {
  var sides: Bool
  func path(in rect: CGRect) -> Path {
    let reach: CGFloat = 4000
    return Path(
      sides
        ? CGRect(x: rect.minX, y: rect.minY - reach, width: rect.width, height: rect.height + reach * 2)
        : rect.insetBy(dx: -reach, dy: -reach))
  }
}

struct InviteLink: Identifiable {
  var url: URL
  var id: String { url.absoluteString }
}
