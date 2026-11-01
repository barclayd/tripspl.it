import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitPersistence

struct RepaymentView: View {
  init(tripID: String, settlement: Settlement) {
    self.tripID = tripID
    self.settlement = settlement
  }
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var tripID: String
  var settlement: Settlement
  @State private var amount = ""
  @State private var note = ""
  var body: some View {
    if let trip = model.store.trip(tripID) {
      NavigationStack {
        Form {
          Section {
            Text("Record money that was already transferred outside TripSplit.").font(.subheadline)
            TextField("Amount in \(trip.homeCurrency)", text: $amount).keyboardType(.decimalPad)
            TextField("Note (optional)", text: $note)
          }
          Section {
            Text("This reduces the balance without adding to your trip’s cost.").font(.footnote)
          }
        }.navigationTitle("Record repayment").toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", systemImage: "xmark") { dismiss() }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save repayment", systemImage: "checkmark") {
              model.perform {
                let minor = try Money.parse(amount, currency: trip.homeCurrency)
                guard minor > 0 else { throw MoneyError.invalid }
                let value = Repayment(
                  fromTravellerId: settlement.from, toTravellerId: settlement.to,
                  amountMinor: String(minor), currency: trip.homeCurrency, paidOn: trip.today,
                  note: note)
                try model.store.enqueue(
                  .init(
                    syncEpoch: trip.syncEpoch, type: "repayment.upsert", entityId: value.id,
                    expectedRevision: nil, payload: .repayment(value)), tripID: trip.id)
                model.changed()
                dismiss()
              }
            }
          }
        }.onAppear { amount = Money.input(settlement.amount, currency: trip.homeCurrency) }
      }
    }
  }
}
