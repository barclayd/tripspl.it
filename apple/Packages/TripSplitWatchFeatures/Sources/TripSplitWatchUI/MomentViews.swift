import SwiftUI
import TripSplitDomain
import TripSplitWatchDesign
import TripSplitWatchModel

/// A one-off moment shown in place of the trips list until it's dismissed.
struct MomentView: View {
  let moment: WatchMoment
  @Environment(WatchModel.self) private var model

  var body: some View {
    if let trip = model.trip(moment.tripID) {
      switch moment {
      case .arrived:
        FirstTripView(trip: trip) { dismiss() }
      case .stamped:
        TripDoneView(wrapUp: TripWrapUp(pages: model.pages(for: trip))) { dismiss() }
      }
    }
  }

  private func dismiss() {
    withAnimation(.easeInOut(duration: 0.3)) { model.dismiss(moment) }
  }
}

/// A2 · First trip arrives. A boarding pass drops in and settles at a tilt.
struct FirstTripView: View {
  let trip: TripSnapshot
  let done: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var landed = false

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        BoardingPass(trip: trip)
          .rotationEffect(.degrees(landed ? -3 : reduceMotion ? -3 : 4))
          .offset(y: landed || reduceMotion ? 0 : -90)
          .opacity(landed ? 1 : 0)
          .padding(.top, 6)
        Text("Your trip's here")
          .watchFont(16, .black)
          .padding(.top, 14)
        Text(trip.name)
          .watchFont(12, .bold)
          .foregroundStyle(WatchTheme.ink2)
          .multilineTextAlignment(.center)
          .padding(.top, 3)
        Button(action: done) {
          Text("Let's go").watchFont(16, .black)
        }
        .buttonStyle(PrimaryButtonStyle(height: 42))
        .padding(.top, 14)
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 4)
    }
    .sensoryFeedback(.selection, trigger: landed)
    .task {
      try? await Task.sleep(for: .milliseconds(250))
      withAnimation(
        reduceMotion ? .easeInOut(duration: 0.3) : .spring(response: 0.5, dampingFraction: 0.6)
      ) { landed = true }
    }
  }
}

/// A small paper boarding pass: route codes, dates and a perforated stub with the first flag.
struct BoardingPass: View {
  let trip: TripSnapshot

  private static let paper = Color(hex: 0xFFFDF6)
  private static let stub = Color(hex: 0xFCE9EE)
  private static let ink = Color(hex: 0x23201B)
  private static let muted = Color(hex: 0x7A7368)

  var body: some View {
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 3) {
        Text("BOARDING PASS")
          .font(.system(size: 8, weight: .bold, design: .monospaced))
          .tracking(1)
          .foregroundStyle(Self.muted)
        Text(trip.routeCode)
          .font(.system(size: 15, weight: .black, design: .monospaced))
          .foregroundStyle(Self.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
        Text(trip.dateRange().uppercased())
          .font(.system(size: 8, weight: .bold, design: .monospaced))
          .tracking(0.6)
          .foregroundStyle(Self.muted)
      }
      .padding(.leading, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      Perforation()
        .stroke(Self.muted.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        .frame(width: 1.5)
      Text(trip.stops.first?.flag ?? "✈️")
        .font(.system(size: 13))
        .frame(width: 26)
        .frame(maxHeight: .infinity)
        .background(Self.stub)
    }
    .frame(width: 150, height: 66)
    .background(Self.paper)
    .clipShape(.rect(cornerRadius: 8))
    .shadow(color: WatchTheme.accent.opacity(0.35), radius: 10)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Boarding pass, \(trip.name), \(trip.dateRange())")
  }
}

/// H5 · Trip's done. The trip's stamp thuds onto a passport page with what it came to and who
/// still owes. The trip then sits in Been there.
struct TripDoneView: View {
  let wrapUp: TripWrapUp
  let done: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var phase = Phase.raised

  enum Phase { case raised, struck, settled }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        ZStack {
          RuledPaper()
          TripStamp(wrapUp: wrapUp)
            .scaleEffect(scale)
            .rotationEffect(.degrees(phase == .raised && !reduceMotion ? -4 : -12))
            .opacity(phase == .raised ? 0 : 1)
        }
        .frame(height: 124)
        .background(WatchTheme.paper)
        .clipShape(.rect(cornerRadius: 20))
        Text(wrapUp.headline)
          .watchFont(16, .black)
          .multilineTextAlignment(.center)
          .padding(.top, 8)
        Text(wrapUp.detail)
          .watchFont(12, .bold)
          .foregroundStyle(WatchTheme.ink2)
          .multilineTextAlignment(.center)
          .padding(.top, 2)
        Button(action: done) {
          Text("Done").watchFont(16, .black)
        }
        .buttonStyle(PrimaryButtonStyle(height: 42))
        .padding(.top, 10)
      }
      .padding(.horizontal, 4)
    }
    .sensoryFeedback(trigger: phase) { _, new in new == .struck ? .impact(weight: .heavy) : nil }
    .task {
      try? await Task.sleep(for: .milliseconds(300))
      if reduceMotion {
        withAnimation(.easeInOut(duration: 0.3)) { phase = .struck }
      } else {
        withAnimation(.easeIn(duration: 0.18)) { phase = .struck }
        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.spring(duration: 0.3, bounce: 0.3)) { phase = .settled }
      }
    }
  }

  private var scale: CGFloat {
    guard !reduceMotion else { return 1 }
    switch phase {
    case .raised: return 2.6
    case .struck: return 0.92
    case .settled: return 1
    }
  }
}

/// The large rectangular ink stamp for a finished trip: its flags, places and dates.
struct TripStamp: View {
  let wrapUp: TripWrapUp
  private let ink = WatchTheme.stampInks[2]

  var body: some View {
    VStack(spacing: 4) {
      Text(wrapUp.flags.joined(separator: " ")).font(.system(size: 13))
      Text(wrapUp.places)
        .font(.system(size: 12, weight: .black, design: .monospaced))
        .tracking(1)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
      Text(wrapUp.dates)
        .font(.system(size: 9, weight: .heavy, design: .monospaced))
        .tracking(0.6)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
    .foregroundStyle(ink)
    .padding(.horizontal, 14)
    .frame(width: 160, height: 80)
    .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(ink, lineWidth: 2.5) }
    .overlay { RoundedRectangle(cornerRadius: 14).inset(by: 6).strokeBorder(ink, lineWidth: 1.5) }
    .opacity(0.92)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Stamped: \(wrapUp.places.capitalized), \(wrapUp.dates.capitalized)")
  }
}

/// The torn-here line between a boarding pass and its stub.
struct Perforation: Shape {
  func path(in rect: CGRect) -> Path {
    Path { $0.move(to: .init(x: rect.midX, y: rect.minY)); $0.addLine(to: .init(x: rect.midX, y: rect.maxY)) }
  }
}
