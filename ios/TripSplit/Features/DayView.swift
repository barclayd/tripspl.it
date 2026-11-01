import SwiftUI

struct DayView: View {
  @Environment(AppModel.self) private var model
  var tripID: String
  var attachment: Attachment
  var showsPaneControls = false
  @State private var usesVerticalRail = false
  @State private var tent = false
  @State private var clear = false
  var body: some View {
    if let trip = model.store.trip(tripID) {
      let items = trip.expenses(for: attachment)
      let ledger = Ledger(trip, expenses: trip.expenses(for: attachment))
      ScrollView {
        ViewThatFits(in: .horizontal) {
          if tent {
            HStack(alignment: .top, spacing: 28) {
              header(trip, ledger: ledger).frame(minWidth: 220, maxWidth: .infinity)
              expenseList(trip, items: items).frame(minWidth: 240, maxWidth: .infinity)
            }
          }
          VStack(alignment: .leading, spacing: 26) {
            header(trip, ledger: ledger)
            expenseList(trip, items: items)
          }
        }.pagePadding().padding(.bottom, 18)
      }.background(Theme.background).onGeometryChange(for: Bool.self) {
        $0.size.width > $0.size.height && $0.size.width < 700
      } action: {
        tent = $0
      }
      .safeAreaInset(edge: .bottom) {
        if !usesVerticalRail {
          HStack(spacing: 12) {
            Button("Quick convert", systemImage: "arrow.left.arrow.right") {
              model.showConverter = true
            }.labelStyle(.iconOnly).font(.title3.weight(.bold)).frame(width: 56, height: 56)
              .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            PrimaryButton(
              title: attachment.kind == .leg ? "Add travel" : "Add expense", symbol: "plus"
            ) { model.editExpense(trip: trip, attachment: attachment) }
          }.padding(.horizontal, 20).padding(.bottom, 12).background(Theme.background.opacity(0.96))
        }
      }
      .safeAreaInset(edge: .top) {
        if showsPaneControls {
          HStack {
            Button("Close day", systemImage: "xmark") { model.selectedAttachment = nil }
            Spacer()
            Button(
              model.fullScreenDay ? "Show trip alongside" : "Full screen",
              systemImage: model.fullScreenDay
                ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
            ) { model.fullScreenDay.toggle() }
          }.labelStyle(.iconOnly).buttonStyle(.glass).padding(.horizontal, 20).padding(.vertical, 4)
        }
      }
      .toolbar {
        if usesVerticalRail {
          ToolbarItem(placement: .primaryAction) {
            Button(attachment.kind == .leg ? "Add travel" : "Add expense", systemImage: "plus") {
              model.editExpense(trip: trip, attachment: attachment)
            }
          }
          ToolbarItem {
            Button("Quick convert", systemImage: "arrow.left.arrow.right") {
              model.showConverter = true
            }
          }
        }
        ToolbarItem {
          Menu("Day options", systemImage: "calendar.badge.ellipsis") {
            Button("Clear day", systemImage: "trash", role: .destructive) { clear = true }
          }
        }
      }
      .confirmationDialog(
        "Delete all \(items.count) expenses on this day?", isPresented: $clear,
        titleVisibility: .visible
      ) {
        Button("Delete expenses", role: .destructive) {
          model.perform {
            for item in items { try model.store.deleteExpense(item, tripID: trip.id) }
            model.changed()
          }
        }
      }
      .readVerticalRail($usesVerticalRail)
      .taskRail()
    }
  }
  private func header(_ trip: TripSnapshot, ledger: Ledger) -> some View {
    VStack(alignment: .leading, spacing: 15) {
      Text(attachment.kind == .leg ? "✈️" : trip.stop(for: attachment)?.flag ?? "🌍").font(
        .system(size: 34)
      ).frame(width: 62, height: 62).background(
        Theme.surface, in: RoundedRectangle(cornerRadius: 20))
      if attachment.kind == .day {
        Text(
          "DAY \((trip.days.firstIndex(where: { $0.id == attachment.id }) ?? 0) + 1) OF \(trip.days.count)\(trip.date(for: attachment) == trip.today(for: attachment) ? " · TODAY" : "")"
        ).font(.caption.weight(.black)).tracking(1).foregroundStyle(Theme.accent)
      }
      Text(trip.title(for: attachment)).font(.system(size: 30, weight: .heavy, design: .default))
        .tracking(-1)
      Text(
        attachment.kind == .leg
          ? CivilDate.display(trip.date(for: attachment), format: "EEEE d MMMM")
          : "\(trip.stop(for: attachment)?.place ?? "") · \(trip.stop(for: attachment)?.currency ?? trip.homeCurrency)"
      ).font(.subheadline).foregroundStyle(Theme.secondary)
      Card {
        VStack(alignment: .leading, spacing: 8) {
          Text("Spent + planned").font(.subheadline.weight(.semibold)).foregroundStyle(
            Theme.secondary)
          MoneyText(amount: ledger.total, currency: trip.homeCurrency, size: tent ? 72 : 43)
          Text(
            "\(trip.expenses(for: attachment).filter { $0.status == .paid }.count) paid · \(trip.expenses(for: attachment).filter { $0.status == .planned }.count) planned"
          ).font(.caption).foregroundStyle(Theme.secondary)
          if ledger.unresolved > 0 {
            Text("\(ledger.unresolved) conversion pending · total incomplete").font(.caption)
              .foregroundStyle(Theme.bad)
          }
        }
      }
    }
  }
  private func expenseList(_ trip: TripSnapshot, items: [Expense]) -> some View {
    VStack(alignment: .leading, spacing: 17) {
      if items.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          Image(systemName: attachment.kind == .leg ? "airplane.departure" : "receipt").font(
            .largeTitle
          ).foregroundStyle(Theme.accent)
          Text(attachment.kind == .leg ? "How are you getting there?" : "Nothing here yet").font(
            .headline)
          Text(
            attachment.kind == .leg
              ? "Add the flight, the train, even the taxi to the airport. It all adds up."
              : "Log what you spent, or plan ahead and tick it off later."
          ).font(.subheadline).foregroundStyle(Theme.secondary).lineSpacing(3)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(24).overlay(
          RoundedRectangle(cornerRadius: 22).strokeBorder(
            Theme.secondary.opacity(0.3), style: .init(lineWidth: 1.5, dash: [6, 5])))
      } else {
        VStack(spacing: 0) {
          ForEach(items) { expense in
            HStack(spacing: 12) {
              Button {
                model.toggleExpense(expense, trip: trip)
              } label: {
                CategoryIcon(category: expense.category, paid: expense.status == .paid)
              }.buttonStyle(.plain).accessibilityLabel(
                "Mark \(expense.title) as \(expense.status == .paid ? "planned" : "paid")")
              Button {
                model.editExpense(trip: trip, attachment: attachment, expense: expense)
              } label: {
                HStack {
                  VStack(alignment: .leading, spacing: 5) {
                    Text(expense.title).font(.subheadline.weight(.heavy))
                    Text(
                      expense.status == .paid
                        ? "\(trip.travellers.first(where: { $0.id == expense.paidBy })?.name ?? "Traveller") paid · Split \(expense.splitWith.count) ways"
                        : "Planned · \(expense.splitWith.count) people"
                    ).font(.caption).foregroundStyle(Theme.secondary)
                  }
                  Spacer()
                  VStack(alignment: .trailing, spacing: 5) {
                    Text(Money.format(Money.minor(expense.amountMinor) ?? 0, expense.currency))
                      .font(.subheadline.weight(.heavy))
                    if let home = expense.homeMinor(in: trip.homeCurrency) {
                      Text(
                        expense.currency == trip.homeCurrency
                          ? "\(Money.format(Money.split(home, among: expense.splitWith)[trip.currentTravellerId, default: 0], trip.homeCurrency)) your share"
                          : Money.format(home, trip.homeCurrency)
                      ).font(.caption).foregroundStyle(Theme.secondary)
                    } else {
                      Text("Conversion pending").font(.caption2).foregroundStyle(Theme.bad)
                    }
                  }
                }
              }.buttonStyle(.plain)
            }.padding(.vertical, 17)
            if expense.id != items.last?.id { Divider() }
          }
        }
        if items.contains(where: { $0.status == .planned }) {
          Label(
            "Dashed means planned. Tap the circle once it’s paid.", systemImage: "circle.dashed"
          ).font(.footnote).foregroundStyle(Theme.secondary)
        }
      }
    }
  }
}
