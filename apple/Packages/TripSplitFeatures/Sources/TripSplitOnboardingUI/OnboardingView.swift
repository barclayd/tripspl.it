import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain

/// New trip setup: each answer fills in the boarding pass above it.
public struct OnboardingView: View {
  public init() {
  }
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var forward = true
  @State private var fanned = false
  @State private var rejected = 0
  @FocusState private var inputFocused: Bool

  private var draft: OnboardingDraft { model.onboarding }
  private var step: Int { draft.step }

  public var body: some View {
    VStack(spacing: 0) {
      header
      if !inputFocused {
        passArea.transition(.move(edge: .top).combined(with: .opacity))
      }
      if !fanned {
        ScrollView {
          ZStack(alignment: .topLeading) {
            stepContent.id(step).transition(stepTransition)
          }
          .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively).scrollBounceBehavior(.basedOnSize)
        .transition(.opacity)
      }
      footer
    }
    .background(Theme.background)
    .overlay {
      if step == 6 {
        Celebration(flags: OnboardingCopy.flags(draft)).allowsHitTesting(false)
          .ignoresSafeArea()
      }
    }
    .animation(reduceMotion ? nil : Motion.sheet, value: inputFocused)
    .animation(reduceMotion ? nil : Motion.sheet, value: fanned)
    .onChange(of: model.onboarding) { _, _ in model.saveOnboarding() }
    .onChange(of: step) { _, _ in fanned = false }
    .task { await model.refreshReferenceRates() }
  }

  // MARK: Header

  private var header: some View {
    HStack(spacing: 14) {
      Button(action: close) {
        Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
          .foregroundStyle(Theme.secondary).frame(width: 36, height: 36)
          .background(Theme.inset, in: Circle())
          .frame(width: 44, height: 44).contentShape(Rectangle())
      }.buttonStyle(PressStyle()).accessibilityLabel("Close")
        .accessibilityIdentifier("onboarding.close")
      ProgressTrack(progress: max(0.05, Double(step) / Double(draft.totalSteps)))
        .accessibilityElement()
        .accessibilityLabel("Step \(draft.stepPosition) of \(draft.totalSteps)")
      Button(action: goBack) {
        Text("Back").typeface(14, .heavy, relativeTo: .subheadline, maximum: 1.3)
          .foregroundStyle(Theme.secondary).frame(minWidth: 38, minHeight: 44)
          .contentShape(Rectangle())
      }.buttonStyle(.plain).opacity(canGoBack ? 1 : 0).disabled(!canGoBack)
        .accessibilityIdentifier("onboarding.back")
    }.padding(.horizontal, 12).padding(.top, 4)
  }

  private var canGoBack: Bool { step != 0 && step != 6 }

  // MARK: Boarding pass

  private var passes: [BoardingPassContent] {
    let travelClass = OnboardingCopy.travelClass(
      draft, homePerGBP: model.indicativeRate(from: "GBP", to: draft.currency))
    var passes = BoardingPassContent.itinerary(
      stops: draft.stops, start: draft.startsOn, homeCurrency: draft.currency
    ) { _ in
      [.init("PAX", "\(draft.travellers.count)"), .init("CLASS", travelClass ?? "—")]
    }
    let highlight: BoardingPassContent.Highlight? =
      switch step {
      case 0: .destination
      case 1, 2: .field(1)
      case 3: .field(2)
      case 5: .field(3)
      default: nil
      }
    for index in passes.indices { passes[index].highlight = highlight }
    return passes
  }

  private var passArea: some View {
    ScrollView {
      BoardingPassStack(
        passes: passes, expanded: $fanned, cleared: step == 6,
        open: step == 0 ? { removeStop($0) } as (Int) -> Void : nil
      )
      .modifier(Floating(active: step == 6))
      .padding(.top, 16).padding(.horizontal, 20).padding(.bottom, 4)
      .frame(maxWidth: 560).frame(maxWidth: .infinity)
    }
    .scrollDisabled(!fanned).scrollBounceBehavior(.basedOnSize)
    .fixedSize(horizontal: false, vertical: !fanned)
    .frame(maxHeight: fanned ? .infinity : nil, alignment: .top)
  }

  private func removeStop(_ index: Int) {
    guard model.onboarding.stops.indices.contains(index) else { return }
    Haptics.lightImpact()
    model.onboarding.stops.remove(at: index)
    model.onboarding.reconcileRoute()
    if let zone = model.onboarding.stops.first?.resolvedTimeZone {
      model.onboarding.timeZone = zone
    }
  }

  // MARK: Steps

  private var stepContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      switch step {
      case 0: RouteStep(focus: $inputFocused)
      case 1: DepartureStep()
      case 2: NightsStep()
      case 3: TravellersStep(focus: $inputFocused)
      case 4: HomeCurrencyStep()
      case 5: BudgetStep(focus: $inputFocused)
      default: BonVoyageStep()
      }
    }
    .padding(.top, 22).padding(.horizontal, 20).padding(.bottom, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var stepTransition: AnyTransition {
    if reduceMotion { return .opacity }
    return .asymmetric(
      insertion: .offset(x: forward ? 48 : -48).combined(with: .opacity),
      removal: .opacity.animation(.easeOut(duration: 0.12)))
  }

  // MARK: Footer

  private var footer: some View {
    VStack(spacing: 12) {
      let cheer = OnboardingCopy.cheer(draft)
      Text(cheer).typeface(14, .heavy, relativeTo: .subheadline, maximum: 1.3)
        .foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.75)
        .frame(minHeight: 20).bump(on: cheer)
      Button(action: advance) {
        Text(step == 5 ? "Create trip" : step == 6 ? "Plan getting there" : "Continue")
      }
      .buttonStyle(LipButtonStyle(inactive: !draft.canAdvance))
      .shake(on: rejected)
      .accessibilityIdentifier("onboarding.continue")
      if step == 6 {
        Button("Go to trip") { model.finishOnboarding(planTravel: false) }
          .typeface(15, .heavy, relativeTo: .subheadline, maximum: 1.3)
          .foregroundStyle(Theme.secondary).frame(minHeight: 44)
          .accessibilityIdentifier("onboarding.goToTrip")
      }
    }
    .padding(.top, 10).padding(.horizontal, 20).padding(.bottom, 6)
    .frame(maxWidth: 680).frame(maxWidth: .infinity)
  }

  // MARK: Actions

  private func advance() {
    guard draft.canAdvance else {
      rejected += 1
      Haptics.error()
      return
    }
    inputFocused = false
    forward = true
    switch step {
    case 5:
      withAnimation(stepAnimation) { model.perform { _ = try model.createTrip() } }
      Haptics.success()
    case 6:
      model.finishOnboarding(planTravel: true)
    default:
      if step == 4, draft.budget.isEmpty,
        let rate = model.indicativeRate(from: "GBP", to: draft.currency)
      {
        model.onboarding.budget = String(draft.suggestedBudget(homePerGBP: rate))
      }
      Haptics.selection()
      withAnimation(stepAnimation) { model.onboarding.advanceStep() }
    }
  }

  private func goBack() {
    guard canGoBack else { return }
    inputFocused = false
    forward = false
    withAnimation(stepAnimation) { model.onboarding.previousStep() }
  }

  private func close() {
    if step == 6 {
      model.finishOnboarding(planTravel: false)
    } else {
      model.saveOnboarding()
      dismiss()
    }
  }

  private var stepAnimation: Animation? {
    reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.45)
  }
}

/// The header's chunky progress bar, with a glossy highlight along its fill.
private struct ProgressTrack: View {
  let progress: Double
  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width * min(max(progress, 0), 1)
      ZStack(alignment: .leading) {
        Capsule().fill(Theme.inset)
        Capsule().fill(Theme.accent).frame(width: width)
          .overlay(alignment: .top) {
            if width > 24 {
              Capsule().fill(.white.opacity(0.38)).frame(height: 4)
                .padding(.horizontal, 8).padding(.top, 3)
            }
          }
      }
    }
    .frame(height: 14)
    .animation(Motion.spring, value: progress)
  }
}

/// Bobs the finished boarding pass gently, as if it were being waved about.
private struct Floating: ViewModifier {
  let active: Bool
  @State private var lifted = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content.offset(y: lifted ? -6 : 0).rotationEffect(.degrees(lifted ? -1.5 : 0))
      .onChange(of: active, initial: true) { _, active in
        guard active, !reduceMotion, !lifted else { return }
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(0.8)) {
          lifted = true
        }
      }
  }
}
