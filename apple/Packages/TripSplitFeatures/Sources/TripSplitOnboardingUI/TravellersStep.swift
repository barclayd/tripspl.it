import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain

/// Step 4: everyone splitting costs, each with their own luggage tag.
struct TravellersStep: View {
  let focus: FocusState<Bool>.Binding
  @Environment(AppModel.self) private var model
  @State private var name = ""

  private var travellers: [Traveller] { model.onboarding.travellers }
  private var full: Bool { travellers.count >= OnboardingDraft.maximumTravellers }
  private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

  /// People from earlier trips who aren't on this one yet.
  private var recent: [String] {
    var seen = Set(travellers.map { $0.name.lowercased() })
    seen.insert("you")
    var names: [String] = []
    for trip in model.store.trips {
      for traveller in trip.travellers where !traveller.archived {
        let key = traveller.name.lowercased()
        guard !seen.contains(key) else { continue }
        seen.insert(key)
        names.append(traveller.name)
      }
    }
    return Array(names.prefix(4))
  }

  @Environment(\.onboardingWide) private var wide

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      StepTitle("Who’s coming?", "Everyone who’ll be splitting costs.")
      if !full {
        HStack(spacing: 8) {
          TextField("Add a name", text: $name)
            .typeface(16, .bold, relativeTo: .body, maximum: 1.4).foregroundStyle(Theme.ink)
            .focused(focus).textInputAutocapitalization(.words).autocorrectionDisabled()
            .submitLabel(.done).onSubmit { add(trimmed) }
            .padding(.vertical, 14).padding(.horizontal, 16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.key))
            .accessibilityIdentifier("onboarding.travellerName")
          Button {
            add(trimmed)
          } label: {
            Image(systemName: "plus").font(.system(size: 19, weight: .heavy))
              .foregroundStyle(trimmed.isEmpty ? Theme.tertiary : Theme.accentInk)
              .frame(width: 50, height: 50)
              .background(
                trimmed.isEmpty ? Theme.inset : Theme.accent,
                in: RoundedRectangle(cornerRadius: Theme.Radius.key))
          }.buttonStyle(PressStyle(scale: 0.9)).disabled(trimmed.isEmpty)
            .animation(Motion.bump, value: trimmed.isEmpty)
            .accessibilityLabel("Add traveller").accessibilityIdentifier("onboarding.addTraveller")
        }
        if !recent.isEmpty {
          FlowLayout(spacing: 6) {
            Text("Recent").typeface(12.5, .heavy, relativeTo: .caption, maximum: 1.4)
              .foregroundStyle(Theme.tertiary).padding(.trailing, 2)
            ForEach(recent, id: \.self) { recentName in
              Button {
                add(recentName)
              } label: {
                Text("+ \(recentName)").typeface(13, .heavy, relativeTo: .footnote, maximum: 1.4)
                  .foregroundStyle(Theme.secondary).padding(.vertical, 6).padding(.horizontal, 11)
                  .background(Theme.surface, in: Capsule())
              }.buttonStyle(PressStyle(scale: 0.9)).accessibilityLabel("Add \(recentName)")
            }
          }
        }
      }
      LazyVGrid(
        // The open Duo fits three across; anything narrower keeps two so names don't truncate.
        columns: wide
          ? [GridItem(.adaptive(minimum: 150), spacing: 10)]
          : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
        spacing: 12
      ) {
        ForEach(Array(travellers.enumerated()), id: \.element.id) { index, traveller in
          LuggageTag(
            traveller: traveller, index: index,
            remove: index == 0 ? nil : { remove(traveller) })
        }
      }
      .padding(.top, 4)
    }
  }

  private func add(_ raw: String) {
    let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty, !full else { return }
    let named = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    Haptics.lightImpact()
    withAnimation(Motion.spring) {
      model.onboarding.travellers.append(
        Traveller(name: named, hue: AvatarPalette.hue(at: travellers.count)))
    }
    if raw == trimmed { name = "" }
  }

  private func remove(_ traveller: Traveller) {
    Haptics.lightImpact()
    withAnimation(Motion.spring) {
      model.onboarding.travellers.removeAll { $0.id == traveller.id }
    }
  }
}

/// A traveller's luggage tag: clipped corners, a punched hole and their seat.
private struct LuggageTag: View {
  let traveller: Traveller
  let index: Int
  let remove: (() -> Void)?
  @State private var swung = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var palette: AvatarPalette { AvatarPalette(hue: traveller.hue) }
  private var seat: String {
    let letters = Array("ABCDEF")
    return "\(index + 1)\(letters[index % letters.count])"
  }

  var body: some View {
    Button {
      remove?()
    } label: {
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 1) {
          Text(index == 0 ? "LEAD PASSENGER" : "PASSENGER")
            .typeface(8.5, .black, tracking: 0.14, relativeTo: .caption2, maximum: 1.3)
            .lineLimit(1).minimumScaleFactor(0.7).opacity(0.75)
          Text(traveller.name).typeface(17, .black, relativeTo: .headline, maximum: 1.3)
            .lineLimit(1).truncationMode(.tail)
        }.frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .trailing, spacing: 1) {
          Text("SEAT").typeface(8.5, .black, tracking: 0.14, relativeTo: .caption2, maximum: 1.3)
            .opacity(0.75)
          Text(seat).typeface(15, .black, relativeTo: .subheadline, maximum: 1.3)
        }
      }
      .foregroundStyle(palette.foreground)
      .padding(.leading, 30).padding(.trailing, 12)
      .frame(maxWidth: .infinity, minHeight: 64)
      .background(palette.background, in: LuggageTagShape())
      .overlay(alignment: .leading) {
        Circle().fill(Theme.background)
          .overlay { Circle().strokeBorder(palette.foreground, lineWidth: 2) }
          .frame(width: 11, height: 11).padding(.leading, 11)
      }
      .overlay(alignment: .topTrailing) {
        if remove != nil {
          Image(systemName: "xmark").font(.system(size: 8, weight: .black))
            .foregroundStyle(Theme.background).frame(width: 20, height: 20)
            .background(Theme.ink, in: Circle())
            .overlay { Circle().strokeBorder(Theme.background, lineWidth: 2) }
            .offset(x: 6, y: -6)
        }
      }
      .contentShape(LuggageTagShape())
    }
    .buttonStyle(PressStyle(scale: 0.96))
    .disabled(remove == nil)
    .rotationEffect(.degrees(swung || reduceMotion ? 0 : -16), anchor: UnitPoint(x: 0.06, y: 0.5))
    .opacity(swung || reduceMotion ? 1 : 0)
    .onAppear {
      withAnimation(.timingCurve(0.34, 1.4, 0.64, 1, duration: 0.8)) { swung = true }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(traveller.name), \(index == 0 ? "lead passenger" : "passenger")")
    .accessibilityValue("Seat \(seat)")
    .accessibilityHint(remove == nil ? "" : "Removes \(traveller.name) from the trip")
    .accessibilityAddTraits(remove == nil ? [] : .isButton)
    .accessibilityIdentifier("onboarding.traveller.\(index)")
  }
}

/// Clipped 16pt corners on the hole end, rounded 14pt corners on the other.
private struct LuggageTagShape: Shape {
  func path(in rect: CGRect) -> Path {
    let cut: CGFloat = 16
    let radius: CGFloat = 14
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
    path.addArc(
      tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
      tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius), radius: radius)
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
    path.addArc(
      tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
      tangent2End: CGPoint(x: rect.maxX - radius, y: rect.maxY), radius: radius)
    path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
    path.closeSubpath()
    return path
  }
}
