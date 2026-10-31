import SwiftUI

struct ConvertView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var tripID: String
  var attachment: Attachment
  @State private var amount = "10"
  @State private var from = "EUR"
  @State private var to = "GBP"
  @State private var quote: FXQuote?
  @State private var rateInput = ""
  @State private var message: String?
  @State private var loading = false
  @State private var tent = false
  @State private var quoteRequestID = UUID()
  var result: Int64? {
    guard let value = try? Money.parse(amount, currency: from) else { return nil }
    let verifiedRate = quote.flatMap { $0.from == from && $0.to == to ? $0.rate : nil }
    return try? Money.convert(
      value, from: from, to: to,
      rate: verifiedRate ?? rateInput.replacingOccurrences(of: ",", with: "."))
  }
  var body: some View {
    if let trip = model.store.trip(tripID) {
      NavigationStack {
        ScrollView {
          VStack(spacing: 22) {
            HStack {
              Text(from).font(.title3.weight(.heavy)).padding(14).background(
                Theme.surface, in: Capsule())
              Button("Swap currencies", systemImage: "arrow.left.arrow.right") {
                let old = from
                from = to
                to = old
                quote = nil
                rateInput = ""
                Task { await load() }
              }.font(.title3)
              Text(to).font(.title3.weight(.heavy)).padding(14).background(
                Theme.surface, in: Capsule())
            }
            TextField("Amount", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(
              .center
            ).font(.system(size: 48, weight: .bold, design: .default)).monospacedDigit()
            VStack(alignment: .leading, spacing: 12) {
              Text("THAT’S ABOUT").font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(2).foregroundStyle(Theme.amber)
              if let result {
                if tent {
                  MoneyText(amount: result, currency: to, size: 80).foregroundStyle(.white)
                } else {
                  FlapText(value: Money.format(result, to), count: 12, size: 25)
                }
              } else {
                Text(loading ? "Fetching rate…" : "Rate needed").font(.title.weight(.heavy))
                  .foregroundStyle(.white)
              }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24).background(
              Theme.board, in: RoundedRectangle(cornerRadius: 22))
            if let quote {
              Text(
                "1 \(from) = \(quote.rate) \(to) · \(quote.source) · \(quote.rateDate)\nReference estimate; your card’s charge may differ."
              ).font(.caption).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
            } else {
              VStack(alignment: .leading, spacing: 8) {
                Text(message ?? "Enter a rate to convert offline.").font(.footnote).foregroundStyle(
                  Theme.secondary)
                HStack {
                  Text("1 \(from) =")
                  TextField("Rate", text: $rateInput).keyboardType(.decimalPad).textFieldStyle(
                    .roundedBorder)
                  Text(to)
                }.font(.subheadline)
              }
            }
            if let result, to == trip.homeCurrency, let budget = Money.minor(trip.budgetMinor),
              budget > 0
            {
              let daily = max(1, budget / Int64(max(1, trip.days.count)))
              VStack(spacing: 6) {
                HStack {
                  Text("\(result * 100 / daily)% of a day’s budget")
                  Spacer()
                  Text("\(Money.format(daily, to)) a day")
                }.font(.caption)
                ProgressView(value: min(Double(result) / Double(daily), 1)).tint(
                  result > daily ? Theme.bad : Theme.accent)
              }
            }
            HStack {
              ForEach([1, 5, 10, 20, 50, 100], id: \.self) { value in
                Button("\(value)") {
                  amount = String(value * (Money.precision(from) == 0 ? 100 : 1))
                }.font(.caption.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                  .background(Theme.inset, in: Capsule())
              }
            }
            NumberPad(value: $amount, currency: from)
            PrimaryButton(title: "Log it as an expense", symbol: "plus") {
              var draft = ExpenseDraft(trip: trip, attachment: attachment)
              draft.amount = amount
              draft.currency = from
              if let result, to == trip.homeCurrency {
                if let quote, quote.from == from, quote.to == to {
                  draft.conversion = Conversion(
                    homeAmountMinor: String(result), rate: quote.rate, rateDate: quote.rateDate,
                    source: quote.source, kind: "reference", quoteId: quote.id)
                } else {
                  draft.actualHomeAmount = Money.input(result, currency: to)
                }
              }
              dismiss()
              Task {
                try? await Task.sleep(for: .milliseconds(300))
                model.expenseDraft = draft
                model.persistDraft()
              }
            }.disabled((try? Money.parse(amount, currency: from)) ?? 0 <= 0)
          }.pagePadding()
        }.background(Theme.background).navigationTitle("Quick convert")
          .navigationBarTitleDisplayMode(.inline).toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Close", systemImage: "xmark") { dismiss() }
            }
          }.onGeometryChange(for: Bool.self) {
            $0.size.width > $0.size.height
          } action: {
            tent = $0
          }
      }.task {
        from = trip.stop(for: attachment)?.currency ?? "EUR"
        to = trip.homeCurrency
        await load()
      }.taskRail()
    }
  }
  private func load() async {
    let requestID = UUID()
    quoteRequestID = requestID
    let requestedFrom = from
    let requestedTo = to
    let requestedDate =
      model.store.trip(tripID)?.date(for: attachment) ?? CivilDate.today(timeZone: "UTC")
    loading = true
    defer { if quoteRequestID == requestID { loading = false } }
    do {
      let response = try await model.sync.api.quote(
        from: requestedFrom, to: requestedTo, date: requestedDate, token: nil)
      guard quoteRequestID == requestID, from == requestedFrom, to == requestedTo else { return }
      guard response.from == requestedFrom, response.to == requestedTo,
        response.requestedDate == requestedDate
      else {
        throw ServiceError(
          code: "fx_mismatch",
          message: "The returned quote did not match these currencies. Try again or enter a rate.")
      }
      quote = response
      message = nil
    } catch { if quoteRequestID == requestID { message = error.localizedDescription } }
  }
}
