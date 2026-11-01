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
  @Environment(\.horizontalSizeClass) private var sizeClass
  @State private var forward = true
  @State private var landscape = false
  @State private var verticalRail = false
  @State private var fanned = false
  @State private var rejected = 0
  @State private var originNearby = false
  @FocusState private var inputFocused: Bool

  private var draft: OnboardingDraft { model.onboarding }
  private var step: Int { draft.step }

  /// Compact on the phone; on the open Duo a step sidebar in landscape, a full pass above the
  /// step in portrait.
  private enum Layout { case compact, sidebar, pane }
  private var layout: Layout {
    guard sizeClass == .regular else { return .compact }
    return landscape ? .sidebar : .pane
  }

  public var body: some View {
    NavigationStack {
      Group {
        switch layout {
        case .compact: compactLayout
        case .sidebar: sidebarLayout
        case .pane: paneLayout
        }
      }
      .background(Theme.background)
      .environment(\.onboardingWide, layout != .compact)
      .toolbarVisibility(verticalRail ? .automatic : .hidden, for: .navigationBar)
      .toolbar {
        if verticalRail {
          ToolbarItemGroup(placement: .cancellationAction) {
            Button("Close", systemImage: "xmark", action: close)
              .accessibilityIdentifier("onboarding.close")
            if canGoBack {
              Button("Back", systemImage: "chevron.backward", action: goBack)
                .accessibilityIdentifier("onboarding.back")
            }
          }
        }
      }
    }
    .readVerticalRail($verticalRail)
    .taskRail()
    .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { landscape = $0 }
    .animation(reduceMotion ? nil : Motion.sheet, value: inputFocused)
    .animation(reduceMotion ? nil : Motion.sheet, value: fanned)
    .onChange(of: model.onboarding) { _, _ in model.saveOnboarding() }
    .onChange(of: step) { _, _ in fanned = false }
    .task { await model.refreshReferenceRates() }
  }

  // MARK: Compact

  private var compactLayout: some View {
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
    .overlay { celebration.ignoresSafeArea() }
  }

  @ViewBuilder private var celebration: some View {
    if step == 6 {
      Celebration(flags: OnboardingCopy.flags(draft)).allowsHitTesting(false)
    }
  }

  // MARK: Open landscape

  /// The pass and every step down the left, so you can see what's answered and jump back.
  private var sidebarLayout: some View {
    HStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
              Text("New trip").typeface(26, .heavy, tracking: -0.02, relativeTo: .title, maximum: 1.3)
                .foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
              Spacer(minLength: 8)
              Text(step == 6 ? "All done" : "Step \(draft.stepPosition) of \(draft.totalSteps)")
                .typeface(13, .bold, relativeTo: .footnote, maximum: 1.3)
                .foregroundStyle(Theme.tertiary)
            }
            progress
          }
          TripPass(
            OnboardingCopy.tripPass(draft, size: .sidebar), size: .sidebar, cleared: step == 6
          )
          .modifier(Floating(active: step == 6))
          stepList
        }
        .padding(.top, 24).padding(.leading, 22).padding(.trailing, 20).padding(.bottom, 20)
      }
      .scrollBounceBehavior(.basedOnSize)
      .frame(width: 340)
      .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
      VStack(spacing: 0) {
        ScrollView {
          ZStack(alignment: .topLeading) {
            stepContent.id(step).transition(stepTransition)
          }
          .frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively).scrollBounceBehavior(.basedOnSize)
        footer
      }
      // Leaves a gutter for the round controls when the bar isn't carrying them.
      .padding(.trailing, verticalRail ? 0 : 50)
      .overlay(alignment: .topTrailing) { if !verticalRail { paneControls } }
      .overlay { celebration }
      .clipped()
    }
  }

  private var stepList: some View {
    VStack(spacing: 2) {
      ForEach(Array(draft.flowSteps.filter { $0 != 6 }.enumerated()), id: \.element) { index, target in
        stepRow(index: index, target: target)
      }
    }
  }

  private func stepRow(index: Int, target: Int) -> some View {
    let current = target == step
    let done = step == 6 || (draft.reached(target) && !current)
    let title = OnboardingCopy.stepTitle(target)
    return Button {
      guard done, step != 6 else { return }
      inputFocused = false
      forward = false
      Haptics.selection()
      withAnimation(stepAnimation) { model.onboarding.revisit(target) }
    } label: {
      HStack(spacing: 12) {
        ZStack {
          Circle().fill(done ? Theme.good : current ? Theme.accent : Theme.inset)
          if done {
            Image(systemName: "checkmark").font(.system(size: 12, weight: .black))
              .foregroundStyle(.white)
          } else {
            Text("\(index + 1)").font(.system(size: 13, weight: .heavy))
              .foregroundStyle(current ? .white : Theme.tertiary)
          }
        }
        .frame(width: 28, height: 28)
        VStack(alignment: .leading, spacing: 1) {
          Text(title).typeface(15, .heavy, relativeTo: .subheadline, maximum: 1.3)
            .foregroundStyle(done || current ? Theme.ink : Theme.tertiary)
          if done {
            Text(OnboardingCopy.answer(target, draft))
              .typeface(13, .semibold, relativeTo: .footnote, maximum: 1.3)
              .foregroundStyle(Theme.secondary).lineLimit(1)
          }
        }
        Spacer(minLength: 4)
        if done, step != 6 {
          Text("Edit").typeface(12, .heavy, relativeTo: .caption, maximum: 1.3)
            .foregroundStyle(Theme.tertiary)
        }
      }
      .padding(.vertical, 9).padding(.horizontal, 12)
      .background(current ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 16))
      .contentShape(RoundedRectangle(cornerRadius: 16))
    }
    .buttonStyle(PressStyle(scale: 0.98))
    .disabled(!(done && step != 6))
    .accessibilityElement(children: .combine)
    .accessibilityValue(done ? "Done" : current ? "Current step" : "Not started")
    .accessibilityHint(done && step != 6 ? "Edit this answer" : "")
    .accessibilityIdentifier("onboarding.step.\(target)")
  }

  /// Close and Back as round buttons when the bar isn't showing them.
  private var paneControls: some View {
    VStack(spacing: 10) {
      roundButton("xmark", label: "Close", identifier: "onboarding.close", action: close)
      if canGoBack {
        roundButton(
          "chevron.backward", label: "Back", identifier: "onboarding.back", action: goBack)
      }
    }
    .padding(.top, 12).padding(.trailing, 14)
  }

  private func roundButton(
    _ symbol: String, label: String, identifier: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 15, weight: .bold))
        .foregroundStyle(Theme.ink).frame(width: 40, height: 40)
        .background(Theme.surface, in: Circle())
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .frame(width: 44, height: 44).contentShape(Rectangle())
    }
    .buttonStyle(PressStyle(scale: 0.9)).accessibilityLabel(label)
    .accessibilityIdentifier(identifier)
  }

  // MARK: Open portrait

  /// The full pass above the step, centred in a calm column.
  private var paneLayout: some View {
    VStack(spacing: 0) {
      header
      ScrollView {
        VStack(alignment: .leading, spacing: 4) {
          TripPass(
            OnboardingCopy.tripPass(draft, size: .full), size: .full, cleared: step == 6
          )
          .modifier(Floating(active: step == 6))
          .padding(.top, 14).padding(.horizontal, 20)
          ZStack(alignment: .topLeading) {
            stepContent.id(step).transition(stepTransition)
          }
        }
        .frame(maxWidth: 640).frame(maxWidth: .infinity)
      }
      .scrollDismissesKeyboard(.interactively).scrollBounceBehavior(.basedOnSize)
      footer
    }
    .overlay { celebration.ignoresSafeArea() }
  }

  // MARK: Header

  private var header: some View {
    HStack(spacing: 14) {
      if !verticalRail { backButton }
      progress
      if !verticalRail { closeButton }
    }.padding(.horizontal, 12).padding(.top, verticalRail ? 12 : 4)
  }

  private var progress: some View {
    ProgressTrack(progress: draft.progress)
      .accessibilityElement()
      .accessibilityLabel("Step \(draft.stepPosition) of \(draft.totalSteps)")
  }

  private var closeButton: some View {
    Button(action: close) {
      Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
        .foregroundStyle(Theme.secondary).frame(width: 36, height: 36)
        .background(Theme.inset, in: Circle())
        .frame(width: 44, height: 44).contentShape(Rectangle())
    }.buttonStyle(PressStyle()).accessibilityLabel("Close")
      .accessibilityIdentifier("onboarding.close")
  }

  /// An ink circle that fades out where there's nowhere to go back to.
  private var backButton: some View {
    let size: CGFloat = layout == .pane ? 40 : 36
    return Button(action: goBack) {
      Image(systemName: "arrow.left").font(.system(size: size * 0.42, weight: .semibold))
        .foregroundStyle(Theme.background).frame(width: size, height: size)
        .background(Theme.ink, in: Circle())
        .frame(width: 44, height: 44).contentShape(Rectangle())
    }
    .buttonStyle(PressStyle(scale: 0.88)).accessibilityLabel("Back")
    .accessibilityIdentifier("onboarding.back")
    .opacity(canGoBack ? 1 : 0).allowsHitTesting(canGoBack).accessibilityHidden(!canGoBack)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: canGoBack)
  }

  private var canGoBack: Bool { step != 0 && step != 6 }

  // MARK: Boarding pass

  private var passes: [BoardingPassContent] {
    let travelClass = OnboardingCopy.travelClass(
      draft, homePerGBP: model.indicativeRate(from: "GBP", to: draft.currency))
    var passes = BoardingPassContent.itinerary(
      stops: draft.stops, start: draft.reached(1) ? draft.startsOn : nil,
      homeCurrency: draft.currency,
      origin: draft.origin
    ) { _ in
      [.init("PAX", "\(draft.travellers.count)"), .init("CLASS", travelClass ?? "—")]
    }
    let highlight: BoardingPassContent.Highlight? =
      switch step {
      case 0, 8: .destination
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
  }

  // MARK: Steps

  private var stepContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      switch step {
      case 0: RouteStep(focus: $inputFocused)
      case 8: LeavingFromStep(focus: $inputFocused, nearby: $originNearby)
      case 1: DepartureStep()
      case 2: NightsStep()
      case 3: TravellersStep(focus: $inputFocused)
      case 4: HomeCurrencyStep()
      case 5: BudgetStep(focus: $inputFocused)
      default: BonVoyageStep()
      }
    }
    .padding(.top, layout == .sidebar ? 34 : 22)
    .padding(.horizontal, layout == .sidebar ? 34 : 20).padding(.bottom, 8)
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
    .padding(.top, 10).padding(.horizontal, layout == .sidebar ? 34 : 20)
    .padding(.bottom, layout == .sidebar ? 16 : 6)
    .frame(maxWidth: layout == .compact ? 680 : layout == .pane ? 640 : 628)
    .frame(maxWidth: .infinity)
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

extension EnvironmentValues {
  /// Steps lay themselves out for the open Duo: bigger titles, two months, a budget card.
  @Entry var onboardingWide = false
}
