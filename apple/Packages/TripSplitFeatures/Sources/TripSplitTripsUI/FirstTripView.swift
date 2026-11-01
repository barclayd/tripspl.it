import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitNetworking
import TripSplitSync

/// The Trips tab before there are any: what TripSplit is for, with the first trip a tap away.
///
/// The first launch plays it in: the plane lands on the card, each reason rises and has its
/// emoji stamped down, and a sheen crosses the button. Later launches, and Reduce Motion, show
/// it at rest.
struct FirstTripView<Header: View>: View {
  init(sidebar: Bool, @ViewBuilder header: () -> Header) {
    self.sidebar = sidebar
    self.header = header()
    _played = State(initialValue: Self.hasPlayed)
  }

  /// The open Duo's leading column, where the card runs a little larger.
  let sidebar: Bool
  let header: Header
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var played: Bool
  /// Today's rate for the convert reason, when the cached reference rates don't have it.
  @State private var quoted: String?

  /// Whether everything is in its final place, which the entrance animates towards.
  private var settled: Bool { played || reduceMotion }
  private static var key: String { "hasSeenFirstLaunch" }
  private static var hasPlayed: Bool {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--first-launch") { return false }
    #endif
    return UserDefaults.standard.bool(forKey: key)
  }
  /// The design's ease-out, `cubic-bezier(.2, .8, .2, 1)`.
  private static func easeOut(_ duration: Double) -> Animation {
    .timingCurve(0.2, 0.8, 0.2, 1, duration: duration)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        header
        VStack(alignment: .leading, spacing: 16) {
          card
          VStack(spacing: 10) {
            ForEach(Array(reasons.enumerated()), id: \.element.title) { index, reason in
              ReasonRow(reason: reason, settled: settled, delay: 0.09 * Double(index))
            }
          }
        }
      }
      .pagePadding().padding(.bottom, 12)
    }
    .scrollBounceBehavior(.basedOnSize)
    .scrollEdgeEffectHidden(sidebar, for: .top)
    .scrollEdgeEffectHidden(true, for: .bottom)
    .safeAreaInset(edge: .bottom, spacing: 0) { planButton }
    .background(Theme.background)
    .task { await loadRate() }
    .onAppear {
      guard !played else { return }
      played = true
      UserDefaults.standard.set(true, forKey: Self.key)
    }
  }

  // MARK: Card

  private var card: some View {
    ZStack(alignment: .bottomTrailing) {
      // Two lines set tight, as `lineHeight` below the font's own clips the descenders.
      VStack(alignment: .leading, spacing: sidebar ? -9 : -8) {
        Text("Your next")
        Text("trip")
      }
      .typeface(sidebar ? 40 : 36, .heavy, tracking: -0.05, relativeTo: .largeTitle, maximum: 1.3)
      .foregroundStyle(Theme.ink)
      .padding(.top, 24).padding(.horizontal, 24).padding(.bottom, 30)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
      .opacity(settled ? 1 : 0).offset(y: settled ? 0 : 14)
      .animation(Self.easeOut(0.5), value: settled)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Your next trip").accessibilityAddTraits(.isHeader)
      // Flies in from the bottom left and lands overhanging the corner, clear of the title.
      Text("✈️").font(.system(size: sidebar ? 52 : 46))
        .scaleEffect(settled ? 1 : 0.7)
        .rotationEffect(.degrees(settled ? 0 : 18))
        .offset(x: settled ? -14 : -154, y: settled ? 14 : 74)
        .opacity(settled ? 1 : 0)
        .animation(Self.easeOut(1.1).delay(0.15), value: settled)
        .accessibilityHidden(true)
    }
  }

  // MARK: Reasons

  private var reasons: [Reason] {
    [
      Reason(
        emoji: "🧳", hue: 340, title: "Your travel companion",
        detail: "Built for travellers who want more trip for their money."),
      Reason(
        emoji: "🗺️", hue: 200, title: "See the full cost",
        detail: "Plan every stop and know what the whole trip costs before you go."),
      Reason(
        emoji: "💷", hue: 65, title: "Stay on budget",
        detail: "See what’s left for today, not just the whole trip."),
      Reason(
        emoji: "👯", hue: 300, title: "Split it with friends",
        detail: "Know who owes who before the bill arrives."),
      Reason(
        emoji: "📅", hue: 235, title: "Track every day",
        detail: "A running balance for each day and each place."),
      Reason(emoji: "💱", hue: 155, title: "Convert on the spot", detail: conversion),
      Reason(
        emoji: "⌚", hue: 20, title: "On your wrist too",
        detail: "Check balances at a glance and update your budget with ease."),
    ]
  }

  /// Euros into the home currency, or dollars for someone whose home is the euro.
  private var pair: (foreign: String, home: String) {
    let home = model.displayCurrency
    return (home == "EUR" ? "USD" : "EUR", home)
  }

  /// "€10 → £8.62, right when you need it." at today's rate into the home currency.
  private var conversion: String {
    let (foreign, home) = pair
    let ten = 10 * Money.factor(foreign)
    guard let rate = quoted ?? model.referenceRates?.rate(from: foreign, to: home),
      let converted = try? Money.convert(ten, from: foreign, to: home, rate: rate)
    else { return "Any price in \(home), right when you need it." }
    let amounts = "\(Money.format(ten, foreign, compact: true)) → \(Money.format(converted, home))"
    return "\(amounts), right when you need it."
  }

  /// Refreshes the reference rates, then asks for the one pair when they still don't have it.
  private func loadRate() async {
    await model.refreshReferenceRates()
    let (foreign, home) = pair
    guard model.sync.configured, model.referenceRates?.rate(from: foreign, to: home) == nil
    else { return }
    let today = CivilDate.today(timeZone: TimeZone.current.identifier)
    quoted = try? await model.sync.api.quote(from: foreign, to: home, date: today, token: nil).rate
  }

  // MARK: Button

  /// Pinned under the reasons, which fade as they scroll beneath it.
  private var planButton: some View {
    VStack(spacing: 0) {
      LinearGradient(
        colors: [Theme.background.opacity(0), Theme.background], startPoint: .top,
        endPoint: .bottom
      )
      .frame(height: 28).allowsHitTesting(false)
      PrimaryButton(title: "Plan your first trip", symbol: "plus") { model.showOnboarding = true }
        .overlay { Sheen(swept: settled) }
        .accessibilityIdentifier("trips.planFirstTrip")
        .opacity(settled ? 1 : 0).offset(y: settled ? 0 : 14)
        .animation(Self.easeOut(0.6).delay(0.8), value: settled)
        .padding(.horizontal, Theme.Spacing.screen).padding(.bottom, 10)
        .frame(maxWidth: 680).frame(maxWidth: .infinity)
        .background(Theme.background)
    }
  }
}

private struct Reason {
  let emoji: String
  let hue: Double
  let title: String
  let detail: String
}

/// One reason: a tinted emoji tile, then a title and a line about it.
private struct ReasonRow: View {
  let reason: Reason
  let settled: Bool
  /// How far behind the first row this one plays in.
  let delay: Double

  var body: some View {
    HStack(spacing: 12) {
      Text(reason.emoji).font(.system(size: 22))
        .stamped(settled: settled, delay: 0.7 + delay)
        .frame(width: 44, height: 44)
        .background(
          Color(light: OKLCH(0.94, 0.045, reason.hue), dark: OKLCH(0.32, 0.06, reason.hue)),
          in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(reason.title)
          .typeface(15, .heavy, tracking: -0.02, relativeTo: .subheadline, maximum: 1.5)
          .foregroundStyle(Theme.ink)
        Text(reason.detail).typeface(12.5, relativeTo: .caption, maximum: 1.5)
          .foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 10).padding(.horizontal, 12)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .accessibilityElement(children: .combine)
    .opacity(settled ? 1 : 0).offset(y: settled ? 0 : 14)
    .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.6).delay(0.45 + delay), value: settled)
  }
}

private struct Stamp {
  var scale = 1.0
  var angle = 0.0
  var opacity = 1.0
}

extension View {
  /// Lands like a passport stamp once `settled` turns true: oversized and tilted, a squash, then
  /// still. At rest from the start when it's already settled.
  fileprivate func stamped(settled: Bool, delay: Double) -> some View {
    keyframeAnimator(initialValue: Stamp(), trigger: settled) { content, stamp in
      content.scaleEffect(stamp.scale).rotationEffect(.degrees(stamp.angle))
        .opacity(stamp.opacity)
    } keyframes: { _ in
      KeyframeTrack(\.opacity) {
        MoveKeyframe(0)
        LinearKeyframe(0, duration: delay)
        LinearKeyframe(1, duration: 0.33)
      }
      KeyframeTrack(\.scale) {
        MoveKeyframe(1.9)
        LinearKeyframe(1.9, duration: delay)
        SpringKeyframe(0.92, duration: 0.33, spring: .snappy)
        SpringKeyframe(1, duration: 0.22, spring: .bouncy)
      }
      KeyframeTrack(\.angle) {
        MoveKeyframe(-14)
        LinearKeyframe(-14, duration: delay)
        SpringKeyframe(3, duration: 0.33, spring: .snappy)
        SpringKeyframe(0, duration: 0.22, spring: .bouncy)
      }
    }
  }
}

/// A band of light that crosses the button once, then waits out of sight past its far edge.
private struct Sheen: View {
  let swept: Bool

  var body: some View {
    GeometryReader { proxy in
      let band = proxy.size.width * 0.3
      LinearGradient(
        colors: [.white.opacity(0), .white.opacity(0.35), .white.opacity(0)],
        startPoint: UnitPoint(x: 0, y: 0.4), endPoint: UnitPoint(x: 1, y: 0.6)
      )
      .frame(width: band)
      .offset(x: swept ? band * 3.4 : -band * 1.2)
      .animation(.easeOut(duration: 0.9).delay(1.25), value: swept)
    }
    // The button sits 5pt above its lip, which the light shouldn't cross.
    .mask(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
    .padding(.bottom, 5)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
