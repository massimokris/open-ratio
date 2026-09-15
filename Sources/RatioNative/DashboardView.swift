import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 184)
            Rectangle().fill(RatioTheme.line).frame(width: 1)
            VStack(spacing: 0) {
                topBar
                Hairline()
                if model.session.isDemo { demoBanner; Hairline() }
                Group {
                    switch model.page {
                    case .today: TodayView()
                    case .history: HistoryView()
                    case .preferences: PreferencesView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(RatioTheme.background)
        }
        .font(.system(size: 12, design: .monospaced))
        .frame(minWidth: 840, minHeight: 650)
        .background(RatioTheme.background)
        .sheet(isPresented: $model.tourPresented) { TourView().environmentObject(model) }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) { RatioMark(); Text("ratio").font(.system(size: 24, weight: .medium, design: .monospaced)).tracking(-1.5) }
                .padding(.top, 43).padding(.bottom, 42).padding(.horizontal, 23)
            Eyebrow(text: "Your balance").padding(.horizontal, 23).padding(.bottom, 13)
            ForEach(AppModel.Page.allCases, id: \.self) { page in
                Button { model.page = page } label: {
                    HStack(spacing: 10) {
                        Image(systemName: page == .today ? "circle.lefthalf.filled" : page == .history ? "clock" : "slider.horizontal.3")
                            .frame(width: 15)
                        Text(page.rawValue).lineLimit(1)
                        Spacer()
                        if model.page == page { Rectangle().fill(RatioTheme.create).frame(width: 3, height: 15) }
                    }.font(.system(size: 11, weight: model.page == page ? .semibold : .regular, design: .monospaced))
                        .padding(.leading, 13).padding(.trailing, 9).frame(height: 39)
                        .background(model.page == page ? RatioTheme.line.opacity(0.45) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.horizontal, 10).padding(.bottom, 3)
            }
            Spacer()
            Button(action: model.showTour) {
                Label("How it works", systemImage: "questionmark.circle").font(.system(size: 10, design: .monospaced))
            }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.bottom, 18)
            Hairline().padding(.horizontal, 20)
            VStack(alignment: .leading, spacing: 6) {
                Label("Only on this Mac", systemImage: "lock").font(.system(size: 9, design: .monospaced))
                Text("A little more intention.").font(.system(size: 8, design: .monospaced)).foregroundStyle(.tertiary)
            }.foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 20)
        }.background(RatioTheme.sidebar)
    }
    private var topBar: some View {
        HStack {
            Text(model.page.rawValue).font(.system(size: 11, weight: .medium, design: .monospaced))
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(model.session.isPaused ? RatioTheme.unknown : RatioTheme.create).frame(width: 5, height: 5)
                Text(model.statusText).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            Button(action: model.togglePause) {
                Image(systemName: model.session.isPaused ? "play" : "pause").frame(width: 23, height: 23)
            }.buttonStyle(.plain).help(model.session.isPaused ? "Resume tracking" : "Pause tracking")
                .accessibilityLabel(model.session.isPaused ? "Resume tracking" : "Pause tracking")
        }.padding(.horizontal, 28).frame(height: 65)
    }
    private var demoBanner: some View {
        HStack(spacing: 10) {
            Text("DEMO").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
                .padding(.horizontal, 7).padding(.vertical, 4).background(RatioTheme.unknown.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
            Text("Fictional activity. Your real day is safe.").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            Spacer()
            Button("Reset", action: model.resetDemo).buttonStyle(.plain).font(.system(size: 10, design: .monospaced))
            Button("Exit demo", action: model.exitDemo).buttonStyle(QuietButtonStyle())
        }.padding(.horizontal, 28).padding(.vertical, 10).foregroundStyle(RatioTheme.unknown)
    }
}
