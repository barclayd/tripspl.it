import SwiftUI
import TripSplitDomain
import TripSplitWatchDesign
import TripSplitWatchModel

/// One spend on a day: category tile, title, who paid and what it came to at home.
struct ExpenseRow: View {
  let expense: Expense
  let pages: TripPages

  var body: some View {
    let home = pages.homeAmount(expense)
    let original = WatchCurrency.format(
      Money.minor(expense.amountMinor) ?? 0, expense.currency, compact: true)
    let planned = expense.status == .planned
    HStack(spacing: 8) {
      Image(systemName: expense.category.symbol)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(expense.category.tileGlyph)
        .frame(width: 28, height: 28)
        .background(expense.category.tileBackground, in: .rect(cornerRadius: 9))
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 4) {
          Text(expense.title).watchFont(13, .black).lineLimit(2)
          if pages.unsynced.contains(expense.id) { UnsyncedDot() }
        }
        Text(detail(original: original, planned: planned))
          .watchFont(10, .bold)
          .foregroundStyle(WatchTheme.ink2)
          .lineLimit(1)
      }
      Spacer(minLength: 2)
      Text(home.map { WatchCurrency.format($0, pages.currency, compact: true) } ?? original)
        .watchFont(13, .black)
        .foregroundStyle(planned ? WatchTheme.ink2 : .white)
        .lineLimit(1)
        .fixedSize()
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(WatchTheme.card, in: .rect(cornerRadius: 16))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(expense.title), \(original)\(planned ? ", planned" : ""), paid by \(pages.name(expense.paidBy))"
        + (pages.unsynced.contains(expense.id) ? ", waiting for iPhone" : ""))
  }

  /// "€6.40 · Maya", "€6.40 · Planned" or just the payer when it's in the home currency.
  private func detail(original: String, planned: Bool) -> String {
    let who = planned ? "Planned" : pages.name(expense.paidBy)
    return expense.currency == pages.currency ? who : "\(original) · \(who)"
  }
}

/// A spend on Today or a day that can be tapped to edit it in the log flow or delete it.
struct ExpenseItem: View {
  @Environment(WatchModel.self) private var model
  let expense: Expense
  let pages: TripPages
  @State private var choosing = false
  @State private var editing = false

  var body: some View {
    Button {
      choosing = true
    } label: {
      ExpenseRow(expense: expense, pages: pages)
    }
    .buttonStyle(.plain)
    .accessibilityHint("Edit or delete")
    .confirmationDialog(expense.title, isPresented: $choosing, titleVisibility: .visible) {
      Button("Edit") { editing = true }
      Button("Delete", role: .destructive) {
        withAnimation(.snappy) { model.deleteExpense(expense, in: pages.trip) }
      }
    }
    .sheet(isPresented: $editing) {
      LogExpenseView(model: model, trip: pages.trip, editing: expense)
    }
  }
}

/// Marks something logged on the watch that the phone hasn't confirmed yet.
struct UnsyncedDot: View {
  var body: some View {
    Circle()
      .fill(WatchTheme.amber)
      .frame(width: 6, height: 6)
      .accessibilityHidden(true)
  }
}
