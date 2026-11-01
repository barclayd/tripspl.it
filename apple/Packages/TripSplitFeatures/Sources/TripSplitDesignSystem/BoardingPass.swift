import SwiftUI
import TripSplitDomain

/// What a boarding pass shows, independent of where the itinerary comes from.
package struct BoardingPassContent: Identifiable, Hashable, Sendable {
  package struct Field: Hashable, Sendable {
    package init(_ label: String, _ value: String) {
      self.label = label
      self.value = value
    }
    package var label: String
    package var value: String
  }

  /// Which part of the pass the current step is asking about.
  package enum Highlight: Hashable, Sendable {
    /// One of the three fields, numbered from 1.
    case field(Int)
    case destination
  }

  package init(
    id: String, from: String, fromName: String, to: String, toName: String, flag: String,
    leg: String, fields: [Field], stubLabel: String, stubValue: String,
    highlight: Highlight? = nil, placeholder: Bool = false
  ) {
    self.id = id
    self.from = from
    self.fromName = fromName
    self.to = to
    self.toName = toName
    self.flag = flag
    self.leg = leg
    self.fields = fields
    self.stubLabel = stubLabel
    self.stubValue = stubValue
    self.highlight = highlight
    self.placeholder = placeholder
  }

  package var id: String
  package var from: String
  package var fromName: String
  package var to: String
  package var toName: String
  package var flag: String
  package var leg: String
  package var fields: [Field]
  package var stubLabel: String
  package var stubValue: String
  package var highlight: Highlight?
  package var placeholder: Bool

  /// One pass per stop plus the flight home, dated by accumulating nights from `start`.
  ///
  /// `fields` supplies the second and third fields for each pass; the first is always the date.
  /// The trip leaves from and returns to `origin`, or a generic Home until one is picked.
  /// With no stops yet, returns a single placeholder pass asking where to.
  package static func itinerary(
    stops: [Stop], start: String?, homeCurrency: String, origin: TripOrigin? = nil,
    fields: (Int) -> [Field] = { _ in [] }
  ) -> [BoardingPassContent] {
    let home = origin?.passCode ?? "HOME"
    let homeName = origin?.place ?? "Home"
    func date(_ value: String?) -> Field {
      Field("DATE", value.map { CivilDate.display($0, format: "d MMM").uppercased() } ?? "—")
    }
    guard let last = stops.last else {
      return [
        BoardingPassContent(
          id: "placeholder", from: home, fromName: homeName, to: "???", toName: "Where to?",
          flag: "", leg: "BOARDING PASS", fields: [date(start)] + fields(0), stubLabel: "NIGHTS",
          stubValue: "—", placeholder: true)
      ]
    }
    let total = stops.count + 1
    var day = start
    var passes: [BoardingPassContent] = []
    for (index, stop) in stops.enumerated() {
      let previous = index > 0 ? stops[index - 1] : nil
      passes.append(
        BoardingPassContent(
          id: "l\(index)\(stop.countryCode)\(stop.place)", from: previous?.passCode ?? home,
          fromName: previous?.place ?? homeName, to: stop.passCode, toName: stop.place,
          flag: stop.flag, leg: "LEG \(index + 1) OF \(total)",
          fields: [date(day)] + fields(index), stubLabel: stop.nights == 1 ? "NIGHT" : "NIGHTS",
          stubValue: "\(stop.nights)"))
      day = day.map { CivilDate.adding(stop.nights, to: $0) }
    }
    passes.append(
      BoardingPassContent(
        id: "home\(last.place)", from: last.passCode, fromName: last.place, to: home,
        toName: homeName, flag: origin?.flag ?? ConversionCurrency.forCurrency(homeCurrency).flag,
        leg: "LEG \(total) OF \(total)", fields: [date(day)] + fields(stops.count),
        stubLabel: "WELCOME", stubValue: "HOME"))
    return passes
  }

  /// Passes for a saved trip, one per travel leg, with that leg's travel spend.
  ///
  /// A leg with no stop at one end starts or finishes at the trip's origin.
  package static func passes(for trip: TripSnapshot) -> [BoardingPassContent] {
    let legs = trip.orderedLegs
    let stops = Dictionary(trip.stops.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let pax = "\(trip.activeTravellers.count)"
    let home = trip.origin?.passCode ?? "HOME"
    let homeName = trip.origin?.place ?? "Home"
    let homeFlag = trip.origin?.flag ?? ConversionCurrency.forCurrency(trip.homeCurrency).flag
    return legs.enumerated().map { index, leg in
      let source = leg.fromStopId.flatMap { stops[$0] }
      let destination = leg.toStopId.flatMap { stops[$0] }
      let spend = trip.travelSpend(on: leg)
      return BoardingPassContent(
        id: leg.id, from: source?.passCode ?? home, fromName: source?.place ?? homeName,
        to: destination?.passCode ?? home, toName: destination?.place ?? homeName,
        flag: destination?.flag ?? homeFlag,
        leg: "LEG \(index + 1) OF \(legs.count)",
        fields: [
          Field("DATE", CivilDate.display(leg.date, format: "d MMM").uppercased()),
          Field("PAX", pax),
          Field(
            "TRAVEL",
            spend == 0 ? "ADD" : Money.format(spend, trip.homeCurrency, compact: true)),
        ],
        stubLabel: destination.map { $0.nights == 1 ? "NIGHT" : "NIGHTS" } ?? "WELCOME",
        stubValue: destination.map { "\($0.nights)" } ?? "HOME")
    }
  }
}

extension TripSnapshot {
  /// Outbound first, home last, transfers by date in between.
  package var orderedLegs: [TravelLeg] {
    func rank(_ kind: TravelLeg.Kind) -> Int {
      switch kind {
      case .outbound: 0
      case .transfer: 1
      case .return: 2
      }
    }
    return legs.sorted { (rank($0.kind), $0.date) < (rank($1.kind), $1.date) }
  }

  /// Expenses on a leg, plus travel expenses on a transfer's day.
  package func travelExpenses(on leg: TravelLeg) -> [Expense] {
    expenses.filter { expense in
      if expense.attachment == Attachment(kind: .leg, id: leg.id) { return true }
      guard let dayId = leg.dayId else { return false }
      return expense.attachment == Attachment(kind: .day, id: dayId)
        && expense.category.group == .travel
    }
  }

  /// Home-currency spend on a leg, plus travel spend on a transfer's day.
  package func travelSpend(on leg: TravelLeg) -> Int64 {
    let list = travelExpenses(on: leg)
    return list.isEmpty ? 0 : Ledger(self, expenses: list).total
  }
}

/// Three-letter codes for the pass, using city codes rather than airports (London is LON).
enum PassCode {
  private static let places = [
    "Lisbon": "LIS", "Porto": "OPO", "Seville": "SVQ", "Zermatt": "ZMT", "Tokyo": "TYO",
    "Kyoto": "KYO", "Osaka": "OSA", "Rome": "ROM", "Florence": "FLR", "Bangkok": "BKK",
    "Koh Lanta": "LNT", "London": "LON", "Paris": "PAR", "New York": "NYC", "Barcelona": "BCN",
  ]
  private static let countries = [
    "PT": "LIS", "ES": "BCN", "FR": "PAR", "IT": "ROM", "GR": "ATH", "HR": "SPU", "CH": "ZRH",
    "IS": "REK", "JP": "TYO", "TH": "BKK", "VN": "HAN", "ID": "DPS", "US": "NYC", "MX": "MEX",
    "MA": "RAK", "AU": "SYD", "GB": "LON", "IE": "DUB",
  ]

  /// A known city, the country's hub when the place is the whole country, otherwise the
  /// place's first three letters.
  static func code(place: String, countryCode: String) -> String {
    if let code = places[place] { return code }
    if place == CountryMetadata.country(countryCode)?.name, let code = countries[countryCode] {
      return code
    }
    let letters = place.filter(\.isLetter)
    return String((letters.isEmpty ? countryCode : letters).prefix(3)).uppercased()
  }
}

extension Stop {
  package var passCode: String { PassCode.code(place: place, countryCode: countryCode) }
}

extension TripOrigin {
  package var passCode: String { PassCode.code(place: place, countryCode: countryCode) }
}

/// A flag-tinted boarding pass with a tear-off stub.
package struct BoardingPass: View {
  package init(_ content: BoardingPassContent) {
    self.content = content
  }
  package var content: BoardingPassContent

  package static let height: CGFloat = 160
  private static let stub: CGFloat = 88

  package var body: some View {
    let palette = PassPalette(flag: content.flag)
    VStack(spacing: 0) {
      header(palette)
      HStack(spacing: 0) {
        HStack(spacing: 10) {
          Barcode(key: content.id + "v", length: 110, axis: .vertical)
            .foregroundStyle(Theme.ink).opacity(0.85).frame(width: 12)
            .clipShape(RoundedRectangle(cornerRadius: 2))
          VStack(alignment: .leading, spacing: 0) {
            route(palette)
            Spacer(minLength: 4)
            fields(palette)
          }
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        stub(palette)
      }
    }
    .foregroundStyle(Theme.ink)
    .frame(height: Self.height)
    .background(palette.body)
    .clipShape(PassShape(stub: Self.stub))
    .compositingGroup()
    .shadow(color: .black.opacity(0.14), radius: 7, y: 8)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }

  private var accessibilityText: String {
    var parts = [content.leg.capitalized, "\(content.fromName) to \(content.toName)"]
    parts += content.fields.map { "\($0.label.capitalized) \($0.value)" }
    parts.append("\(content.stubValue) \(content.stubLabel.lowercased())")
    return parts.joined(separator: ", ")
  }

  private func header(_ palette: PassPalette) -> some View {
    HStack(spacing: 0) {
      HStack(spacing: 6) {
        Image(systemName: "airplane").font(.system(size: 12, weight: .bold))
        Text("TRIPSPLIT AIR").font(.system(size: 10.5, weight: .black)).tracking(1.05)
          .lineLimit(1)
        Spacer(minLength: 8)
        Text(content.leg).font(.system(size: 9, weight: .black)).tracking(0.72).opacity(0.85)
          .lineLimit(1).layoutPriority(1)
      }
      .padding(.leading, 14).padding(.trailing, 12)
      Text("PASS").font(.system(size: 10, weight: .black)).tracking(1.4)
        .frame(width: Self.stub, height: 30)
        .overlay(alignment: .leading) { DashedRule(color: .white.opacity(0.55)) }
    }
    .foregroundStyle(.white)
    .frame(height: 30)
    .background(palette.band)
    .overlay(alignment: .bottom) { palette.stripe.frame(height: 4) }
  }

  private func route(_ palette: PassPalette) -> some View {
    HStack(alignment: .top, spacing: 6) {
      airport("FROM", content.from, content.fromName, colour: palette.text, palette: palette)
      ZStack(alignment: .top) {
        Arc().stroke(Theme.secondary, style: .init(lineWidth: 1.4, dash: [3.5, 3]))
        Image(systemName: "airplane").font(.system(size: 15, weight: .bold))
          .foregroundStyle(palette.plane).padding(.top, 2)
      }
      .frame(minWidth: 30, maxWidth: .infinity).frame(height: 40).padding(.top, 6)
      airport(
        "TO", content.to, content.toName,
        colour: content.placeholder ? Theme.tertiary : palette.text, palette: palette,
        trailing: true
      )
      .padding(.horizontal, 6).padding(.bottom, 2)
      .background(
        content.highlight == .destination ? palette.highlight : .clear,
        in: RoundedRectangle(cornerRadius: 10)
      )
      .padding(.horizontal, -6)
      .animation(.easeOut(duration: 0.3), value: content.highlight)
    }
  }

  private func airport(
    _ label: String, _ code: String, _ name: String, colour: Color, palette: PassPalette,
    trailing: Bool = false
  ) -> some View {
    VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
      Text(label).font(.system(size: 8.5, weight: .black)).tracking(1).foregroundStyle(
        palette.text)
      Text(code).font(.system(size: 26, weight: .black)).tracking(-0.26).foregroundStyle(colour)
        .lineLimit(1).fixedSize()
      Text(name).font(.system(size: 11.5, weight: .heavy)).lineLimit(1).frame(
        maxWidth: 86, alignment: trailing ? .trailing : .leading)
    }
  }

  private func fields(_ palette: PassPalette) -> some View {
    HStack(spacing: 6) {
      ForEach(Array(content.fields.prefix(3).enumerated()), id: \.offset) { index, field in
        VStack(alignment: .leading, spacing: 0) {
          Text(field.label).font(.system(size: 8.5, weight: .black)).tracking(1)
            .foregroundStyle(palette.text)
          Text(field.value).font(.system(size: 13, weight: .black)).lineLimit(1)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          content.highlight == .field(index + 1) ? palette.highlight : .clear,
          in: RoundedRectangle(cornerRadius: 8)
        )
        .padding(.horizontal, -6)
        .animation(.easeOut(duration: 0.3), value: content.highlight)
      }
    }
  }

  private func stub(_ palette: PassPalette) -> some View {
    VStack(spacing: 0) {
      Text(content.flag.isEmpty ? "?" : content.flag).font(.system(size: 24))
      Spacer(minLength: 0)
      VStack(spacing: 0) {
        Text(content.stubLabel).font(.system(size: 8.5, weight: .black)).tracking(1)
          .foregroundStyle(palette.text)
        Text(content.stubValue).font(.system(size: 19, weight: .black)).lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      Spacer(minLength: 0)
      Barcode(key: content.id, length: 66, axis: .horizontal)
        .foregroundStyle(Theme.ink).opacity(0.85).frame(width: 66, height: 20)
    }
    // 11 rather than the design's 10 so a stacked pass's barcode doesn't peek out below the front pass.
    .padding(EdgeInsets(top: 9, leading: 8, bottom: 11, trailing: 8))
    .frame(width: Self.stub)
    .overlay(alignment: .leading) { DashedRule(color: Theme.line2) }
  }
}

/// The pass outline: rounded card with semicircle notches where the stub tears off.
struct PassShape: Shape {
  var stub: CGFloat
  func path(in rect: CGRect) -> Path {
    let card = Path(roundedRect: rect, cornerRadius: 18, style: .continuous)
    let x = rect.maxX - stub
    var notches = Path()
    notches.addEllipse(in: CGRect(x: x - 9, y: rect.minY - 9, width: 18, height: 18))
    notches.addEllipse(in: CGRect(x: x - 9, y: rect.maxY - 9, width: 18, height: 18))
    return card.subtracting(notches)
  }
}

struct Arc: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.minY + rect.height * 0.75))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + rect.width * 0.98, y: rect.minY + rect.height * 0.75),
      control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.05))
    return path
  }
}

struct DashedRule: View {
  var color: Color
  var body: some View {
    GeometryReader { proxy in
      Path { path in
        path.move(to: CGPoint(x: 1, y: 0))
        path.addLine(to: CGPoint(x: 1, y: proxy.size.height))
      }.stroke(color, style: .init(lineWidth: 2, dash: [4, 4]))
    }.frame(width: 2)
  }
}

/// A deterministic barcode: FNV-1a hash of the key seeds an LCG for bar and gap widths.
package struct Barcode: View {
  package enum Axis { case horizontal, vertical }
  package init(key: String, length: CGFloat, axis: Axis = .horizontal) {
    self.key = key
    self.length = length
    self.axis = axis
  }
  var key: String
  var length: CGFloat
  var axis: Axis

  package var body: some View {
    let bars = Self.bars(key: key, length: length)
    Canvas { context, size in
      for bar in bars {
        let rect =
          axis == .horizontal
          ? CGRect(x: bar.start, y: 0, width: bar.width, height: size.height)
          : CGRect(x: 0, y: bar.start, width: size.width, height: bar.width)
        context.fill(Path(rect), with: .foreground)
      }
    }
    .accessibilityHidden(true)
  }

  struct Bar {
    var start: CGFloat
    var width: CGFloat
  }

  static func bars(key: String, length: CGFloat) -> [Bar] {
    var hash: UInt32 = 2_166_136_261
    for unit in (key.isEmpty ? "x" : key).utf16 {
      hash ^= UInt32(unit)
      hash = hash &* 16_777_619
    }
    var state = hash
    func random() -> Double {
      state = state &* 1_664_525 &+ 1_013_904_223
      return Double(state) / 4_294_967_296
    }
    var bars: [Bar] = []
    var x: CGFloat = 0
    while x < length {
      let width = CGFloat(1 + Int(random() * 3))
      let gap = CGFloat(1 + Int(random() * 2))
      bars.append(Bar(start: x, width: width))
      x += width + gap
    }
    return bars
  }
}

/// A shuffleable stack of passes: swipe the front pass up or aside to send it to the back, tap
/// to fan the stack out, tap a fanned pass to open it.
package struct BoardingPassStack: View {
  /// Pass `expanded` to own the fan state, for example to hide other content while fanned.
  package init(
    passes: [BoardingPassContent], expanded: Binding<Bool>? = nil, cleared: Bool = false,
    open: ((Int) -> Void)? = nil
  ) {
    self.passes = passes
    self.expandedBinding = expanded
    self.cleared = cleared
    self.open = open
  }

  package var passes: [BoardingPassContent]
  package var cleared: Bool
  package var open: ((Int) -> Void)?
  private var expandedBinding: Binding<Bool>?

  private enum Leaving: Equatable {
    case up
    case side(CGFloat)
  }

  @State private var localExpanded = false
  @State private var front = 0
  @State private var drag: CGSize = .zero
  @State private var dragging = false
  @State private var leaving: Leaving?
  @State private var tucking = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let gap: CGFloat = 12
  private var count: Int { passes.count }
  private var frontIndex: Int { count == 0 ? 0 : front % count }

  private var expanded: Bool {
    get { expandedBinding?.wrappedValue ?? localExpanded }
    nonmutating set {
      if let expandedBinding { expandedBinding.wrappedValue = newValue } else {
        localExpanded = newValue
      }
    }
  }
  private var fanned: Bool { expanded && count > 1 }

  private var height: CGFloat {
    fanned
      ? CGFloat(count) * (BoardingPass.height + Self.gap) - Self.gap
      : BoardingPass.height + CGFloat(min(max(count - 1, 0), 2)) * 10
  }

  package var body: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .top) {
        ForEach(Array(passes.enumerated()), id: \.element.id) { index, pass in
          card(pass, index: index)
        }
      }
      .frame(height: height, alignment: .top)
      .frame(maxWidth: .infinity)
      .animation(
        reduceMotion ? nil : .timingCurve(0.34, 1.25, 0.64, 1, duration: 0.55), value: fanned
      )
      .contentShape(Rectangle())
      .gesture(shuffle, isEnabled: !fanned && count >= 2)
      .overlay(alignment: .topTrailing) {
        if cleared {
          Stamp(delay: 0.35) {
            Text("CLEARED").font(.system(size: 16, weight: .black)).tracking(1.9)
              .foregroundStyle(Theme.accentText).padding(.horizontal, 11).padding(.vertical, 5)
              .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
              .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accentText, lineWidth: 3))
          }
          .padding(.trailing, 104).padding(.top, 58).allowsHitTesting(false)
          .accessibilityLabel("Cleared")
        }
      }
      if count > 1 { hint }
    }
    .onChange(of: passes.map(\.id)) { _, ids in
      if front >= ids.count { front = 0 }
    }
    .sensoryFeedback(.impact(weight: .light), trigger: front)
  }

  private func card(_ pass: BoardingPassContent, index: Int) -> some View {
    let pos = (index - frontIndex + count) % max(count, 1)
    let transform = transform(index: index, pos: pos)
    return BoardingPass(pass)
      .scaleEffect(transform.scale, anchor: .bottom)
      .rotationEffect(.degrees(transform.rotation), anchor: .bottom)
      .offset(x: transform.x, y: transform.y)
      .opacity(transform.opacity)
      .zIndex(Double(fanned ? count - index : count - pos))
      .animation(reduceMotion ? nil : animation(pos: pos), value: transform)
      .onTapGesture { tap(index) }
      .allowsHitTesting(fanned || pos == 0)
      .accessibilityHidden(!fanned && pos != 0)
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { tap(index) }
      .accessibilityActions {
        if !fanned && count > 1 {
          Button("Next pass") { advance() }
          Button("Show all passes") { expanded = true }
        }
        if fanned { Button("Stack passes") { expanded = false } }
      }
  }

  private struct CardTransform: Equatable {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rotation: Double = 0
    var scale: CGFloat = 1
    var opacity: Double = 1
  }

  private func transform(index: Int, pos: Int) -> CardTransform {
    if fanned { return CardTransform(y: CGFloat(index) * (BoardingPass.height + Self.gap)) }
    guard pos == 0 else {
      return CardTransform(
        y: CGFloat(pos) * 10, scale: 1 - CGFloat(pos) * 0.05, opacity: pos > 2 ? 0 : 1)
    }
    switch leaving {
    case .up: return CardTransform(y: -165, rotation: -3, scale: 1.03)
    case .side(let direction): return CardTransform(x: direction * 440, rotation: direction * 16)
    case nil: break
    }
    if dragging, abs(drag.height) > abs(drag.width) {
      let y = drag.height < 0 ? drag.height : drag.height * 0.2
      return CardTransform(y: y, rotation: y * 0.015, scale: 1 + min(0.03, -min(y, 0) / 3000))
    }
    return CardTransform(x: drag.width, rotation: drag.width * 0.05)
  }

  private func animation(pos: Int) -> Animation? {
    if !fanned && pos == 0 {
      switch leaving {
      case .up: return .timingCurve(0.3, 0, 0.5, 1, duration: 0.23)
      case .side: return .timingCurve(0.4, 0, 0.6, 1, duration: 0.28)
      case nil: if dragging { return nil }
      }
    }
    if tucking && pos == count - 1 { return Motion.tuck }
    return Motion.spring
  }

  private var shuffle: some Gesture {
    DragGesture(minimumDistance: 6)
      .onChanged { value in
        guard leaving == nil else { return }
        dragging = true
        drag = value.translation
      }
      .onEnded { value in
        let dx = value.translation.width
        let dy = value.translation.height
        dragging = false
        let vertical = abs(dy) > abs(dx)
        if vertical && dy < -45 {
          send(.up)
        } else if !vertical && abs(dx) > 60 {
          send(.side(dx < 0 ? -1 : 1))
        } else {
          drag = .zero
        }
      }
  }

  private func send(_ direction: Leaving) {
    guard !reduceMotion else {
      drag = .zero
      advance()
      return
    }
    leaving = direction
    let pause: Duration = direction == .up ? .milliseconds(230) : .milliseconds(260)
    Task { @MainActor in
      try? await Task.sleep(for: pause)
      leaving = nil
      drag = .zero
      tucking = true
      front = (front + 1) % max(count, 1)
      try? await Task.sleep(for: .milliseconds(800) - pause)
      tucking = false
    }
  }

  private func advance() {
    guard count > 1 else { return }
    front = (front + 1) % count
  }

  private func tap(_ index: Int) {
    if fanned {
      if let open { open(index) } else { expanded = false }
    } else if count > 1 {
      expanded = true
    } else {
      open?(0)
    }
  }

  private var hint: some View {
    HStack {
      HStack(spacing: 5) {
        if !fanned {
          ForEach(0..<count, id: \.self) { index in
            Capsule().fill(index == frontIndex ? Theme.accent : Theme.line2)
              .frame(width: index == frontIndex ? 16 : 6, height: 6)
          }
        }
      }
      .animation(reduceMotion ? nil : .timingCurve(0.34, 1.56, 0.64, 1, duration: 0.35), value: frontIndex)
      .accessibilityHidden(true)
      Spacer()
      if fanned {
        Button("Stack them") { expanded = false }
          .font(.system(size: 12.5, weight: .heavy)).foregroundStyle(Theme.secondary)
          .buttonStyle(.plain).accessibilityLabel("Stack passes")
      }
    }
    .padding(.horizontal, 4).padding(.top, 10).frame(height: 32, alignment: .bottom)
  }
}

extension BoardingPassStack {
  /// A trip's passes; opening a pass hands back its travel leg.
  package init(trip: TripSnapshot, cleared: Bool = false, open: ((TravelLeg) -> Void)? = nil) {
    let legs = trip.orderedLegs
    self.init(
      passes: BoardingPassContent.passes(for: trip), cleared: cleared,
      open: open.map { open in
        { index in if legs.indices.contains(index) { open(legs[index]) } }
      })
  }
}
