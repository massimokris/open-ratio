import AppKit
import SwiftUI

/// The entire primary product: eight rows on a 44-point grid.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedHistoryDay: String?
    var showPreferences: () -> Void = {}
    var body: some View {
        VStack(spacing: 0) {
            RatioSummaryView(summary: model.summary)
            Group {
                if model.page == .preferences {
                    PreferencesView()
                } else {
                    VStack(spacing: 0) {
                        statusRow
                        Group {
                            if model.page == .history { HistoryView(selectedDay: $selectedHistoryDay) }
                            else { TodayView() }
                        }
                        .frame(width: 360, height: 220)
                        .clipped()
                    }
                }
            }
            .frame(width: 360, height: 264)
            .clipped()
            footer
        }
        .font(RatioTheme.font())
        .tracking(RatioTypography.letterSpacing)
        .lineSpacing(RatioTheme.lineSpacing())
        .foregroundStyle(RatioTheme.text)
        .frame(width: 360, height: 352)
        .background(RatioTheme.background)
        .preferredColorScheme(model.appearance.colorScheme)
        .onChange(of: model.page) { _ in selectedHistoryDay = nil }
        .onChange(of: model.session.isDemo) { _ in selectedHistoryDay = nil }
        .contextMenu {
            Button("Settings…", action: showPreferences)
            Button("How It Works…", action: model.showTour)
            Divider()
            Button(model.session.isDemo ? "Exit Demo" : "Try Demo") {
                if model.session.isDemo { model.exitDemo() } else { model.startDemo() }
            }
            if model.session.isDemo {
                Menu("Demo Source") {
                    ForEach(model.session.availableDemoSources) { source in
                        Button(source.name) { model.selectDemoSource(source) }
                    }
                }
            }
            Button("Undo Reset", action: model.undoResetToday).disabled(!model.canUndoReset)
            Button("Export CSV…", action: model.exportActivityCSV)
            Button("Show Data Folder", action: model.revealDataDirectory)
            Menu("Appearance") {
                ForEach(AppModel.Appearance.allCases, id: \.self) { appearance in
                    Button(appearance.rawValue) { model.appearance = appearance }
                }
            }
        }
    }
    private var statusRow: some View {
        Group {
            if model.page == .history {
                historyStatusRow
            } else {
                trackingStatusRow
            }
        }
        .frame(width: 360, height: 44)
        .overlay(alignment: .bottom) { Hairline() }
    }
    private var historyStatusRow: some View {
        Group {
            if let day = selectedHistoryDay {
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        historyStatusTitle
                        Spacer(minLength: 0)
                        Text(HistoryFormatting.dateLabel(for: day)).fixedSize()
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 9)
                    .frame(width: 272, height: 44)
                    Button { selectedHistoryDay = nil } label: {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 13))
                            .foregroundStyle(RatioTheme.text)
                            .frame(width: 88, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PanelButtonStyle())
                    .overlay(alignment: .leading) { Rectangle().fill(RatioTheme.line).frame(width: 0.5) }
                    .accessibilityLabel("Back to daily history")
                    .help("Back to daily history")
                }
            } else {
                HStack(spacing: 8) {
                    historyStatusTitle
                    Spacer(minLength: 8)
                    Text("\(model.session.ledger.days.count) DAYS")
                        .fixedSize().padding(.trailing, 16)
                }
                .padding(.leading, 16)
            }
        }
        .foregroundStyle(model.storageNotice == nil ? RatioTheme.secondary : RatioTheme.unknown)
    }
    private var historyStatusTitle: some View {
        Text(statusTitle)
            .lineLimit(1)
            .help(model.storageNotice ?? "Recorded days")
            .onTapGesture { if model.storageNotice != nil { showPreferences() } }
            .pointingHandCursor(model.storageNotice != nil)
    }
    private var trackingStatusRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(statusTitle).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                Text(PanelFormatting.elapsed(model.summary.totalSeconds))
            }
            .foregroundStyle(model.storageNotice == nil ? RatioTheme.secondary : RatioTheme.unknown)
            .padding(.leading, 16)
            .padding(.trailing, 9)
            .frame(width: 272, height: 44)
            .contentShape(Rectangle())
            .help(model.storageNotice ?? model.statusText)
            .onTapGesture { if model.storageNotice != nil { showPreferences() } }
            .pointingHandCursor(model.storageNotice != nil)
            Button {
                model.page = .today
                model.filter = model.filter == .all ? .unclassified : .all
            } label: {
                Group {
                    if model.unclassifiedCount > 0 {
                        Text("\(model.unclassifiedCount)")
                            .font(RatioTheme.font(weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 19, minHeight: 19)
                            .background(RatioTheme.consume, in: Capsule())
                    } else {
                        Text("✓")
                            .font(.custom("Menlo-Regular", fixedSize: 12))
                            .foregroundStyle(showsCompletedClassification ? Color.black : RatioTheme.text)
                            .frame(width: 19, height: 19)
                    }
                }
                .frame(width: 88, height: 44)
                .background(showsCompletedClassification ? Color.white : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(PanelButtonStyle())
            .overlay(alignment: .leading) { Rectangle().fill(RatioTheme.line).frame(width: 0.5) }
            .help(model.filter == .unclassified ? "Show all activity" : "Show unclassified activity")
            .accessibilityLabel(model.unclassifiedCount == 0
                                 ? "All sources classified" : "\(model.unclassifiedCount) unclassified sources")
            .accessibilityValue(model.filter == .unclassified ? "Showing unclassified" : "Showing all activity")
        }
    }
    private var showsCompletedClassification: Bool {
        model.filter == .unclassified && model.unclassifiedCount == 0
    }
    private var statusTitle: String {
        if model.storageNotice != nil { return model.session.isDemo ? "DEMO · STORAGE" : "STORAGE ERROR" }
        if model.page == .history { return model.session.isDemo ? "DEMO HISTORY" : "HISTORY" }
        if model.filter == .unclassified { return model.session.isDemo ? "DEMO · TO CATEGORIZE" : "TO CATEGORIZE" }
        if model.session.isPaused { return model.session.isDemo ? "DEMO · PAUSED" : "PAUSED" }
        if model.session.isDemo { return "DEMO" }
        if model.indicatorPaused { return "AWAY" }
        if model.browserFallbackNotice != nil { return "APP TRACKING" }
        return "TRACKING"
    }
    private var footer: some View {
        HStack(spacing: 0) {
            footerButton(width: 44, label: model.session.isPaused ? "Resume tracking" : "Pause tracking", action: model.togglePause) {
                if model.session.isPaused {
                    Image(systemName: "play").font(.system(size: 13))
                } else { PauseGlyph() }
            }
            footerButton(width: 44, label: model.page == .history ? "Show today's activity" : "Show history") {
                model.page = model.page == .history ? .today : .history
            } content: {
                if model.page == .history {
                    Image(systemName: "list.dash").font(.system(size: 13))
                } else {
                    HistoryGlyph()
                }
            }
            footerButton(width: 114, label: model.session.isDemo ? "Reset demo" : "Reset today") {
                if model.session.isDemo { model.resetDemo() } else { model.resetToday() }
            } content: { Text("RESET") }
            footerButton(width: 114, label: "Quit Ratio Native") {
                NSApplication.shared.terminate(nil)
            } content: { Text("QUIT") }
            footerButton(width: 44, label: model.page == .preferences ? "Show today's activity" : "Show settings",
                         help: model.storageNotice) {
                model.page = model.page == .preferences ? .today : .preferences
            } content: {
                Image(systemName: "gearshape").font(.system(size: 13))
                    .overlay(alignment: .topTrailing) {
                        if model.storageNotice != nil {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(RatioTheme.unknown)
                                .offset(x: 5, y: -4)
                                .accessibilityHidden(true)
                        }
                    }
            }
        }
        .frame(height: 44)
        .overlay(alignment: .top) { Hairline() }
    }
    private func footerButton<Content: View>(width: CGFloat, label: String, help: String? = nil, action: @escaping () -> Void,
                                            @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            content().frame(width: width, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(FooterButtonStyle())
        .overlay(alignment: .trailing) { Rectangle().fill(RatioTheme.line).frame(width: 0.5) }
        .help(help ?? label)
        .accessibilityLabel(label)
    }
}

private struct PauseGlyph: View {
    var body: some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 0.6).strokeBorder(lineWidth: 1).frame(width: 3.5, height: 11)
            RoundedRectangle(cornerRadius: 0.6).strokeBorder(lineWidth: 1).frame(width: 3.5, height: 11)
        }.accessibilityHidden(true)
    }
}


private struct HistoryGlyph: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 1.5, y: 6))
            path.addCurve(to: CGPoint(x: 6, y: 10.5), control1: CGPoint(x: 1.5, y: 8.5), control2: CGPoint(x: 3.5, y: 10.5))
            path.addCurve(to: CGPoint(x: 10.5, y: 6), control1: CGPoint(x: 8.5, y: 10.5), control2: CGPoint(x: 10.5, y: 8.5))
            path.addCurve(to: CGPoint(x: 6, y: 1.5), control1: CGPoint(x: 10.5, y: 3.5), control2: CGPoint(x: 8.5, y: 1.5))
            path.addCurve(to: CGPoint(x: 1.5, y: 4), control1: CGPoint(x: 4, y: 1.5), control2: CGPoint(x: 2.5, y: 2.5))
            path.move(to: CGPoint(x: 1.5, y: 1.5))
            path.addLine(to: CGPoint(x: 1.5, y: 4))
            path.addLine(to: CGPoint(x: 4, y: 4))
            path.move(to: CGPoint(x: 6, y: 3.5))
            path.addLine(to: CGPoint(x: 6, y: 6))
            path.addLine(to: CGPoint(x: 8, y: 7))
        }
        .stroke(style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}
