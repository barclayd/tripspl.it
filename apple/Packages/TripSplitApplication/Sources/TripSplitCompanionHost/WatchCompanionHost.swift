import Foundation
import Observation
import TripSplitApplication
import TripSplitCompanion
import TripSplitDomain

/// Phone side of the watch companion. Publishes the phone's trips whenever they change and
/// applies watch changes through the same local queue and sync path as the phone's own edits.
@MainActor public final class WatchCompanionHost {
  private let model: AppModel
  private let publisher: @MainActor (CompanionContext) -> Void
  /// Recently rejected watch commands, oldest first, so the watch can explain them.
  private var rejected: [(id: String, reason: String)] = []
  private var scheduled: Task<Void, Never>?
  private let retained: AnyObject?

  public init(
    model: AppModel, retaining transport: AnyObject? = nil,
    publish: @escaping @MainActor (CompanionContext) -> Void
  ) {
    self.model = model
    publisher = publish
    retained = transport
    observe()
  }

  /// Sends the current trips to the watch.
  public func publish() {
    publisher(
      CompanionContext(
        trips: model.store.trips,
        rejected: Dictionary(rejected.map { ($0.id, $0.reason) }, uniquingKeysWith: { $1 })))
  }

  /// Applies a change made on the watch. Re-delivered commands that are already reflected are
  /// skipped so a retry never trips the pending-operation guard.
  public func receive(_ command: CompanionCommand) async {
    guard let trip = model.store.trip(command.tripID) else {
      reject(command, "This trip is no longer on your iPhone.")
      return
    }
    guard !command.isReflected(in: trip) else {
      publish()
      return
    }
    do {
      switch command {
      case .saveExpense(let tripID, var expense):
        if expense.conversion == nil {
          expense.conversion = await estimate(expense, in: trip)
        }
        try model.store.saveExpense(expense, tripID: tripID)
      case .saveRepayment(let tripID, let repayment):
        try model.store.enqueue(
          .init(
            syncEpoch: trip.syncEpoch, type: "repayment.upsert", entityId: repayment.id,
            expectedRevision: nil, payload: .repayment(repayment)), tripID: tripID)
      }
      model.changed()
    } catch {
      reject(command, error.localizedDescription)
    }
  }

  private func reject(_ command: CompanionCommand, _ reason: String) {
    rejected.append((command.id, reason))
    if rejected.count > 20 { rejected.removeFirst() }
    publish()
  }

  /// A reference rate for foreign-currency spends logged on the watch.
  private func estimate(_ expense: Expense, in trip: TripSnapshot) async -> Conversion? {
    guard expense.currency != trip.homeCurrency, model.sync.configured,
      let amount = Money.minor(expense.amountMinor),
      let quote = try? await model.sync.api.quote(
        from: expense.currency, to: trip.homeCurrency, date: trip.date(for: expense.attachment),
        token: nil),
      let home = try? Money.convert(
        amount, from: expense.currency, to: trip.homeCurrency, rate: quote.rate)
    else { return nil }
    return .init(
      homeAmountMinor: String(home), rate: quote.rate, rateDate: quote.rateDate,
      source: quote.source, kind: "reference", quoteId: quote.id)
  }

  /// Publishes shortly after the phone's trips change, coalescing bursts of sync updates.
  private func observe() {
    withObservationTracking {
      _ = model.store.trips
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        self.scheduled?.cancel()
        self.scheduled = Task {
          try? await Task.sleep(for: .milliseconds(400))
          guard !Task.isCancelled else { return }
          self.publish()
        }
        self.observe()
      }
    }
  }
}

#if canImport(WatchConnectivity)
  extension WatchCompanionHost {
    /// Connects to the paired watch over WatchConnectivity.
    public convenience init(model: AppModel) {
      let session = CompanionSession()
      self.init(model: model, retaining: session) { context in
        try? session.publish(context)
      }
      session.onActivate = { [weak self] in self?.publish() }
      session.onCommand = { [weak self] command in
        Task { await self?.receive(command) }
      }
    }
  }
#endif
