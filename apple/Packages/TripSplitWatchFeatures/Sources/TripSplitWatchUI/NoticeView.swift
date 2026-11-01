import SwiftUI
import TripSplitWatchDesign

/// The long look for H1 Landed and H2 Evening wrap: the title, then the body with its lead in
/// bold white, e.g. "**£58.97** spent. £241 under today's budget." The system adds the app's
/// name above and the buttons below.
public struct NoticeView: View {
  let title: String
  let text: String
  let lead: String?

  public init(title: String, body: String, lead: String? = nil) {
    self.title = title
    self.text = body
    self.lead = lead
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .watchFont(17, .black)
        .fixedSize(horizontal: false, vertical: true)
      message
        .watchFont(14, .semibold)
        .foregroundStyle(WatchTheme.ink2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private var message: Text {
    guard let lead, !lead.isEmpty, text.hasPrefix(lead) else { return Text(text) }
    let rest = text.dropFirst(lead.count)
    return Text("\(Text(lead).fontWeight(.heavy).foregroundStyle(.white))\(String(rest))")
  }
}

#Preview("Landed") {
  NoticeView(title: "Welcome to Zermatt 🇨🇭", body: "CHF 1 = £0.93. Convert is set to francs.")
}

#Preview("Evening wrap") {
  NoticeView(
    title: "Day 4 in Porto 🇵🇹", body: "£58.97 spent. £241 under today's budget.", lead: "£58.97")
}
