#if DEBUG
  import SwiftUI
  import TripSplitWatchModel
  import TripSplitWidgetModel
  import TripSplitWidgetUI

  /// Debug only: every widget at its design size, in each look, from the demo trip. Launch with
  /// `--widget-gallery` to page through it, or `--widget-gallery-export` to also write one PNG per
  /// look to Documents/widget-gallery for comparing with the design.
  struct WidgetGallery: View {
    @State private var look = GalleryLook.light
    private let widgets = (try? WatchModel.demo()).map { PhoneWidgets(model: $0) }

    var body: some View {
      NavigationStack {
        ScrollView {
          if let widgets {
            GallerySheet(widgets: widgets, look: look)
          } else {
            ContentUnavailableView("No demo data", systemImage: "square.dashed")
          }
        }
        .background(look.backdrop)
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          Picker("Look", selection: $look) {
            ForEach(GalleryLook.allCases) { Text($0.title).tag($0) }
          }
        }
      }
      .task {
        guard ProcessInfo.processInfo.arguments.contains("--widget-gallery-export"), let widgets
        else { return }
        export(widgets)
      }
    }

    private func export(_ widgets: PhoneWidgets) {
      let folder = URL.documentsDirectory.appending(path: "widget-gallery")
      try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      for look in GalleryLook.allCases {
        let renderer = ImageRenderer(
          content: GallerySheet(widgets: widgets, look: look).frame(width: 402)
            .background(look.backdrop))
        renderer.scale = 3
        guard let data = renderer.uiImage?.pngData() else { continue }
        try? data.write(to: folder.appending(path: "\(look.rawValue).png"))
      }
      print("Widget gallery written to \(folder.path())")
    }
  }

  /// The looks the brief asks for: Home Screen light and dark, Tinted, StandBy, Lock Screen and
  /// Always-On, and amounts hidden while locked.
  enum GalleryLook: String, CaseIterable, Identifiable {
    case light, dark, tinted, standBy, lock, alwaysOn, hidden

    var id: Self { self }

    var title: String {
      switch self {
      case .light: "Light"
      case .dark: "Dark"
      case .tinted: "Tinted"
      case .standBy: "StandBy"
      case .lock: "Lock"
      case .alwaysOn: "Always On"
      case .hidden: "Hidden"
      }
    }

    var look: WidgetLook {
      switch self {
      case .light: WidgetLook()
      case .dark: WidgetLook(dark: true)
      case .tinted: WidgetLook(mode: .accented, dark: true)
      case .standBy: WidgetLook(dark: true, standBy: true)
      case .lock: WidgetLook(mode: .vibrant, dark: true)
      case .alwaysOn: WidgetLook(mode: .vibrant, dark: true, dimmed: true)
      case .hidden: WidgetLook(mode: .vibrant, dark: true, hidesAmounts: true)
      }
    }

    /// The Lock Screen looks only show the accessory families.
    var isLockScreen: Bool { look.mode == .vibrant }

    var backdrop: Color {
      switch self {
      case .light: Color(gallery: 0xE9E4DC)
      case .dark: Color(gallery: 0x0E0D0C)
      case .tinted: Color(gallery: 0x23324A)
      case .standBy, .alwaysOn: .black
      case .lock, .hidden: Color(gallery: 0x2B3A55)
      }
    }

    /// What sits behind a Home Screen tile; Tinted is a frosted pane the system recolours.
    var tile: Color {
      switch self {
      case .tinted: .white.opacity(0.14)
      default: look.palette.background
      }
    }
  }

  /// One look's worth of widgets, laid out like a Home Screen or a Lock Screen.
  struct GallerySheet: View {
    var widgets: PhoneWidgets
    var look: GalleryLook

    var body: some View {
      VStack(alignment: .leading, spacing: 18) {
        if look.isLockScreen { lockScreen } else { homeScreen }
      }
      .padding(.vertical, 20).padding(.horizontal, 32)
      .frame(maxWidth: .infinity, alignment: .leading)
      .environment(\.widgetLook, look.look)
      .environment(\.colorScheme, look.look.dark ? .dark : .light)
      .redacted(reason: look.look.hidesAmounts ? .privacy : [])
    }

    private var tripID: String? { nil }

    @ViewBuilder private var homeScreen: some View {
      let today = widgets.today(tripID: tripID)
      let progress = widgets.progress(tripID: tripID)
      let daily = widgets.daily(tripID: tripID)
      let balances = widgets.balances(tripID: tripID)
      let countdown = widgets.countdown(tripID: tripID)
      let convert = widgets.convert(pair: nil)

      caption("Small")
      Grid(horizontalSpacing: 22, verticalSpacing: 22) {
        GridRow {
          tile(.small, "Today") { if let today { TodaySmallView(figures: today) } }
          tile(.small, "Quick convert") { if let convert { ConvertSmallView(figures: convert) } }
        }
        GridRow {
          tile(.small, "Where you are") { if let progress { WhereSmallView(figures: progress) } }
          tile(.small, "Countdown") { if let countdown { CountdownSmallView(figures: countdown) } }
        }
        GridRow {
          tile(.small, "Who owes who") { if let balances { BalanceSmallView(figures: balances) } }
          tile(.small, "Whole trip") {
            if let trip = widgets.today(tripID: tripID, scope: .trip) {
              TodaySmallView(figures: trip)
            }
          }
        }
        GridRow {
          tile(.small, "No trips") { NoTripsView() }
          tile(.small, "Placeholder") { PlaceholderView() }
        }
      }
      caption("Medium")
      tile(.medium, "Today") { if let today { TodayMediumView(figures: today) } }
      tile(.medium, "Daily spend") { if let daily { DailyMediumView(figures: daily) } }
      tile(.medium, "Departures", board: true) {
        DeparturesMediumView(figures: widgets.departures)
      }
      caption("Large")
      tile(.large, "Today") {
        if let today {
          TodayLargeView(today: today, progress: progress, daily: daily, balances: balances)
        }
      }
    }

    @ViewBuilder private var lockScreen: some View {
      let today = widgets.today(tripID: tripID)
      let progress = widgets.progress(tripID: tripID)
      let daily = widgets.daily(tripID: tripID)
      let balances = widgets.balances(tripID: tripID)
      let countdown = widgets.countdown(tripID: tripID)
      let convert = widgets.convert(pair: nil)

      caption("Circular")
      HStack(spacing: 14) {
        ForEach(BudgetRingStyle.allCases, id: \.self) { style in
          tile(.circular, style.rawValue) {
            if let today { BudgetCircularView(figures: today, style: style) }
          }
        }
      }
      HStack(spacing: 14) {
        tile(.circular, "convert") { if let convert { ConvertCircularView(figures: convert) } }
        tile(.circular, "where") { if let progress { WhereCircularView(figures: progress) } }
        tile(.circular, "countdown") {
          if let countdown { CountdownCircularView(figures: countdown) }
        }
        tile(.circular, "owed") { if let balances { OwedCircularView(figures: balances) } }
      }
      HStack(spacing: 14) {
        tile(.circular, "none") { PlaceholderCircularView(hasTrips: false) }
        tile(.circular, "loading") { PlaceholderCircularView() }
      }
      caption("Rectangular")
      Grid(horizontalSpacing: 14, verticalSpacing: 14) {
        GridRow {
          tile(.rectangular, "Today") { if let today { TodayRectangularView(figures: today) } }
          tile(.rectangular, "Daily spend") {
            if let daily { DailyRectangularView(figures: daily) }
          }
        }
        GridRow {
          tile(.rectangular, "Who owes who") {
            if let balances { BalanceRectangularView(figures: balances) }
          }
          tile(.rectangular, "No trips") { NoTripsRectangularView() }
        }
      }
      caption("Inline")
      VStack(alignment: .leading, spacing: 10) {
        if let today { tile(.inline, nil) { InlineView.today(today) } }
        if let convert { tile(.inline, nil) { InlineView.convert(convert) } }
        if let countdown { tile(.inline, nil) { InlineView.countdown(countdown) } }
        tile(.inline, nil) { InlineView.noTrips }
      }
    }

    private func caption(_ text: String) -> some View {
      Text(text.uppercased()).font(.caption.weight(.semibold)).tracking(1)
        .foregroundStyle(look.look.dark ? .white.opacity(0.6) : .black.opacity(0.5))
        .padding(.top, 6)
    }

    /// A widget at its design size: the system's 16pt margins and rounded container on the Home
    /// Screen, none on the Lock Screen.
    private func tile<Content: View>(
      _ family: GalleryFamily, _ label: String?, board: Bool = false,
      @ViewBuilder content: () -> Content
    ) -> some View {
      VStack(spacing: 6) {
        Group {
          switch family {
          case .small, .medium, .large:
            content()
              .padding(board ? 0 : 16)
              .frame(width: family.size.width, height: family.size.height)
              .background(board ? DeparturesBoard.background : look.tile)
              .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
          case .circular, .rectangular, .inline:
            content()
              .frame(
                width: family.size.width, height: family.size.height,
                alignment: family == .inline ? .leading : .center)
          }
        }
        .foregroundStyle(look.look.palette.ink)
        if let label {
          Text(label).font(.caption2.weight(.medium))
            .foregroundStyle(look.look.dark ? .white.opacity(0.7) : .black.opacity(0.6))
        }
      }
    }
  }

  extension Color {
    /// `Color(hex:)` is package-only in the design system.
    fileprivate init(gallery hex: UInt32) {
      self.init(
        red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255)
    }
  }

  /// The brief's 393 × 852pt sizes.
  enum GalleryFamily {
    case small, medium, large, circular, rectangular, inline

    var size: CGSize {
      switch self {
      case .small: CGSize(width: 158, height: 158)
      case .medium: CGSize(width: 338, height: 158)
      case .large: CGSize(width: 338, height: 354)
      case .circular: CGSize(width: 72, height: 72)
      case .rectangular: CGSize(width: 160, height: 72)
      case .inline: CGSize(width: 234, height: 26)
      }
    }
  }
#endif
