import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitNetworking
import TripSplitPersistence
import TripSplitSharedUI
import TripSplitSync

public struct ExpenseEditor: View {
  public init() {
  }
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var saved: Expense?
  @State private var saving = false
  @State private var wideSheet = false
  @State private var deleteConfirmation = false
  @State private var localError: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  public var body: some View {
    NavigationStack {
      if let draft = model.expenseDraft, let trip = model.store.trip(draft.tripID) {
        Group {
          if let saved {
            ReceiptView(expense: saved, trip: trip) { dismiss() }
          } else {
            ScrollView {
              let layout =
                wideSheet
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: 22))
              layout {
                editorFields(trip, draft: draft).frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(spacing: 14) {
                  NumberPad(value: bind(\.amount, fallback: ""), currency: draft.currency)
                  if let localError { Text(localError).font(.footnote).foregroundStyle(Theme.bad) }
                }.frame(width: wideSheet ? 200 : nil)
              }.pagePadding()
            }.onGeometryChange(for: Bool.self) {
              $0.size.width >= 590
            } action: {
              wideSheet = $0
            }

          }
        }.background(Theme.background).navigationTitle(
          saved == nil ? (draft.expenseID == nil ? "New expense" : "Edit expense") : "All logged"
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(saved == nil ? "Cancel" : "Close", systemImage: "xmark") {
              if saved == nil { model.persistDraft() }
              dismiss()
            }
          }
          ToolbarItem(placement: .confirmationAction) {
            if saved == nil {
              Button("Save", systemImage: "checkmark") { save() }.disabled(
                saving || (try? Money.parse(draft.amount, currency: draft.currency)) ?? 0 <= 0
                  || draft.splitWith.isEmpty)
            }
          }
          if draft.expenseID != nil, saved == nil {
            ToolbarItem {
              Button("Delete expense", systemImage: "trash", role: .destructive) {
                deleteConfirmation = true
              }
            }
          }
        }
        .confirmationDialog(
          "Delete this expense?", isPresented: $deleteConfirmation, titleVisibility: .visible
        ) {
          Button("Delete expense", role: .destructive) {
            model.perform {
              if let expense = trip.expenses.first(where: { $0.id == draft.expenseID }) {
                try model.store.deleteExpense(expense, tripID: trip.id)
                try model.store.removeDocument("expense:" + trip.id)
                model.changed()
                dismiss()
              }
            }
          }
        }
        .interactiveDismissDisabled(saving)
      }
    }.disabled(saving)
      .overlay {
        if saving {
          ProgressView("Saving expense…").font(.subheadline.weight(.semibold)).padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
      }
      .taskRail().presentationDragIndicator(.visible)
  }
  private func editorFields(_ trip: TripSnapshot, draft: ExpenseDraft) -> some View {
    VStack(alignment: .leading, spacing: 22) {
      dayChips(trip, draft)
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          TextField("0", text: bind(\.amount, fallback: "")).keyboardType(.decimalPad)
            .font(.system(size: 56, weight: .bold, design: .default)).monospacedDigit()
            .minimumScaleFactor(0.5).accessibilityLabel("Amount")
          Text(draft.currency).font(.title3.weight(.bold)).foregroundStyle(
            Theme.secondary)
        }
        HStack {
          ForEach(
            Array(
              Set([
                trip.homeCurrency,
                trip.stop(for: draft.attachment)?.currency ?? trip.homeCurrency,
              ])
            ).sorted(), id: \.self
          ) { currency in
            Button(currency) {
              mutate {
                $0.currency = currency
                $0.conversion = nil
                $0.actualHomeAmount = ""
              }
            }.font(.caption.weight(.heavy)).padding(.horizontal, 14).padding(.vertical, 8)
              .background(
                currency == draft.currency ? Theme.accent : Theme.inset, in: Capsule()
              ).foregroundStyle(currency == draft.currency ? .white : Theme.ink)
          }
          Menu {
            ForEach(CurrencyMetadata.codes, id: \.self) { currency in
              Button(currency) {
                mutate {
                  $0.currency = currency
                  $0.conversion = nil
                }
              }
            }
          } label: {
            Label("More", systemImage: "ellipsis").font(.caption.weight(.semibold))
          }
        }
      }
      TextField(
        draft.attachment.kind == .leg ? "e.g. Taxi to the airport" : "What was it?",
        text: bind(\.title, fallback: "")
      ).font(.headline).padding(16).background(
        Theme.inset, in: RoundedRectangle(cornerRadius: 14))
      categoryChips(draft)
      Card(padding: 16) {
        VStack(alignment: .leading, spacing: 18) {
          Picker("Status", selection: bind(\.status, fallback: .paid)) {
            Text("Paid").tag(Expense.Status.paid)
            Text("Planned").tag(Expense.Status.planned)
          }.pickerStyle(.segmented)
          Kicker(title: "Paid by")
          people(trip, draft: draft, split: false)
          HStack {
            Kicker(title: "Split between")
            Spacer()
            Button("Just me") { mutate { $0.splitWith = [trip.currentTravellerId] } }
            Button("Everyone") {
              mutate { $0.splitWith = trip.activeTravellers.map(\.id) }
            }
          }.font(.caption.weight(.bold))
          people(trip, draft: draft, split: true)
          if let amount = try? Money.parse(draft.amount, currency: draft.currency),
            !draft.splitWith.isEmpty
          {
            let shares = Money.split(amount, among: draft.splitWith)
            Text(
              "\(Money.format(shares.values.min() ?? 0, draft.currency))\(Set(shares.values).count > 1 ? "–\(Money.format(shares.values.max() ?? 0, draft.currency))" : "") each · \(draft.splitWith.count) people"
            ).font(.caption).foregroundStyle(Theme.secondary)
          }
        }
      }
      if draft.currency != trip.homeCurrency {
        VStack(alignment: .leading, spacing: 8) {
          Text("Actual charge in \(trip.homeCurrency) (optional)").font(
            .subheadline.weight(.semibold))
          TextField("e.g. 5.52", text: bind(\.actualHomeAmount, fallback: ""))
            .keyboardType(.decimalPad).padding(12).background(
              Theme.inset, in: RoundedRectangle(cornerRadius: 12))
          Text(
            draft.conversion.map {
              "Saved rate: \($0.rate) · \($0.source) · \($0.rateDate)"
            }
              ?? "We’ll try the reference rate when saving. Without a rate, this expense stays visible with conversion pending."
          ).font(.footnote).foregroundStyle(Theme.secondary)
        }
      }
    }
  }
  private func bind<T>(_ keyPath: WritableKeyPath<ExpenseDraft, T>, fallback: T) -> Binding<T> {
    Binding(
      get: { model.expenseDraft?[keyPath: keyPath] ?? fallback },
      set: { value in mutate { $0[keyPath: keyPath] = value } })
  }
  private func mutate(_ update: (inout ExpenseDraft) -> Void) {
    guard var draft = model.expenseDraft else { return }
    update(&draft)
    model.expenseDraft = draft
    model.persistDraft()
  }
  private func dayChips(_ trip: TripSnapshot, _ draft: ExpenseDraft) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(trip.legs.filter { $0.kind == .outbound }) { leg in
          dayChip(leg.title, attachment: .init(kind: .leg, id: leg.id), draft: draft)
        }
        ForEach(trip.days) { day in
          dayChip(
            "\(trip.stops.first(where: { $0.id == day.stopId })?.flag ?? "") \(CivilDate.display(day.date, format: "EEE d"))",
            attachment: .init(kind: .day, id: day.id), draft: draft)
        }
        ForEach(trip.legs.filter { $0.kind != .outbound }) { leg in
          dayChip(leg.title, attachment: .init(kind: .leg, id: leg.id), draft: draft)
        }
      }
    }
  }
  private func dayChip(_ title: String, attachment: Attachment, draft: ExpenseDraft) -> some View {
    Button {
      mutate { $0.attachment = attachment }
    } label: {
      Text(title).font(.caption.weight(.bold)).padding(.horizontal, 13).padding(.vertical, 9)
        .background(draft.attachment == attachment ? Theme.accentSoft : Theme.inset, in: Capsule())
        .foregroundStyle(draft.attachment == attachment ? Theme.accent : Theme.secondary)
    }
  }
  private func categoryChips(_ draft: ExpenseDraft) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack {
        ForEach(
          ExpenseCategory.allCases.filter {
            draft.attachment.kind == .leg
              ? [.flight, .train, .taxi, .transport, .other].contains($0)
              : ![.flight, .train, .taxi].contains($0)
          }, id: \.self
        ) { category in
          Button {
            mutate { $0.category = category }
          } label: {
            Label(category.title, systemImage: category.symbol).font(.caption.weight(.bold))
              .padding(11).background(
                draft.category == category ? Theme.accentSoft : Theme.inset, in: Capsule()
              ).foregroundStyle(draft.category == category ? Theme.accent : Theme.secondary)
          }
        }
      }
    }
  }
  private func people(_ trip: TripSnapshot, draft: ExpenseDraft, split: Bool) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 12) {
        ForEach(trip.activeTravellers) { person in
          let selected = split ? draft.splitWith.contains(person.id) : draft.paidBy == person.id
          Button {
            mutate {
              if split {
                if $0.splitWith.contains(person.id) {
                  $0.splitWith.removeAll { $0 == person.id }
                } else {
                  $0.splitWith.append(person.id)
                }
              } else {
                $0.paidBy = person.id
              }
            }
          } label: {
            VStack(spacing: 5) {
              Avatar(traveller: person, size: 40).padding(3).overlay(
                Circle().stroke(selected ? Theme.accent : .clear, lineWidth: 2))
              Text(person.name).font(.caption2.weight(.bold))
            }.opacity(selected ? 1 : 0.5)
          }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
        }
      }
    }
  }
  private func save() {
    saving = true
    Task {
      do {
        let editing = model.expenseDraft?.expenseID != nil
        let result = try await model.saveExpense()
        saving = false
        if editing {
          model.notify("Saved")
          dismiss()
        } else {
          withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.88)) {
            saved = result
          }
          Haptics.lightImpact()
        }
      } catch {
        saving = false
        localError = error.localizedDescription
      }
    }
  }
}
struct ReceiptView: View {
  init(expense: Expense, trip: TripSnapshot, close: @escaping () -> Void) {
    self.expense = expense
    self.trip = trip
    self.close = close
  }
  var expense: Expense
  var trip: TripSnapshot
  var close: () -> Void
  @State private var printed = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    VStack(spacing: 25) {
      Spacer(minLength: 12)
      ZStack(alignment: .top) {
        Capsule().fill(Color(hex: 0x252224)).frame(height: 14).frame(maxWidth: 320)
        VStack(spacing: 18) {
          Text("TRIPSPLIT").font(.system(size: 22, weight: .black, design: .monospaced)).tracking(4)
          Text(
            "\(trip.stop(for: expense.attachment)?.place.uppercased() ?? "TRAVEL") · \(CivilDate.display(trip.date(for: expense.attachment)).uppercased())"
          ).font(.system(size: 11, weight: .bold, design: .monospaced))
          Divider()
          line(expense.title, Money.format(Money.minor(expense.amountMinor) ?? 0, expense.currency))
          line(
            "IN \(trip.homeCurrency)",
            expense.homeMinor(in: trip.homeCurrency).map { Money.format($0, trip.homeCurrency) }
              ?? "PENDING")
          line(
            "PAID BY",
            trip.travellers.first(where: { $0.id == expense.paidBy })?.name ?? "Traveller")
          line("SPLIT", "\(expense.splitWith.count) PEOPLE")
          Divider()
          line("TOTAL", Money.format(Money.minor(expense.amountMinor) ?? 0, expense.currency))
          HStack(spacing: 3) {
            ForEach(0..<35) { n in Rectangle().frame(width: n % 3 == 0 ? 3 : 1) }
          }.frame(height: 28)
          Text(expense.status.rawValue.uppercased()).font(
            .system(size: 29, weight: .black, design: .monospaced)
          ).padding(10).overlay(RoundedRectangle(cornerRadius: 6).stroke(lineWidth: 3))
            .foregroundStyle(expense.status == .paid ? Color(hex: 0x2E9E63) : Color(hex: 0x4D77B8))
            .rotationEffect(.degrees(-10)).padding(.top, 8)
        }.foregroundStyle(Color(hex: 0x23201B)).padding(24).frame(maxWidth: 294).background(
          Color(hex: 0xFFFDF6)
        ).offset(y: printed || reduceMotion ? 9 : -400)
      }.frame(height: 420, alignment: .top).clipped()
      Text("Saved on this device").font(.caption).foregroundStyle(Theme.secondary)
      Button("Done", action: close).buttonStyle(.borderedProminent)
      Spacer(minLength: 12)
    }.padding(20).frame(maxWidth: .infinity).onAppear {
      withAnimation(reduceMotion ? nil : .easeOut(duration: 1.2)) { printed = true }
    }
  }
  private func line(_ label: String, _ value: String) -> some View {
    HStack(alignment: .top) {
      Text(label.uppercased())
      Spacer()
      Text(value).multilineTextAlignment(.trailing)
    }.font(.system(size: 11, weight: .semibold, design: .monospaced))
  }
}
