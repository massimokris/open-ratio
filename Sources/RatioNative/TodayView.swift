import SwiftUI
import RatioCore

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: model.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        Text("Make space to create.").font(.system(size: 24, weight: .regular, design: .monospaced)).tracking(-1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Eyebrow(text: "Tracked today")
                        Text(ActivityFormatting.duration(model.summary.totalSeconds)).font(.system(size: 17, design: .monospaced))
                    }
                }
                RatioSummaryView(summary: model.summary)
                if let source = model.activeSource { activeSourceCard(source) }
                else if model.summary.activities.isEmpty { emptyState }
                activitySection
            }.padding(28)
        }
    }
    private func activeSourceCard(_ source: ActivitySource) -> some View {
        HStack(spacing: 13) {
            SourceIcon(source: source)
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: model.session.isPaused ? "Paused on" : "In focus now")
                Text(source.name).font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            Spacer()
            if model.session.isDemo {
                Menu {
                    ForEach(model.session.availableDemoSources) { source in
                        Button(source.name) { model.selectDemoSource(source) }
                    }
                } label: {
                    Label("Switch source", systemImage: "arrow.left.arrow.right").font(.system(size: 10, design: .monospaced))
                }.menuStyle(.borderlessButton).fixedSize().padding(.trailing, 12)
                    .accessibilityLabel("Switch demo foreground source")
            }
            CategoryPicker(source: source, category: model.activeCategory) { model.classify(source, as: $0) }
        }.padding(15).background(RatioTheme.panel, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(RatioTheme.line))
    }
    private var emptyState: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: "sparkle").font(.system(size: 20)).foregroundStyle(RatioTheme.create).padding(.top, 3)
            VStack(alignment: .leading, spacing: 8) {
                Text("Your day starts here.").font(.system(size: 13, weight: .medium, design: .monospaced))
                Text("Activity appears as you use your Mac. Choose Create or Consume for each source to find your balance.")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Try demo", action: model.startDemo).buttonStyle(QuietButtonStyle())
                    Button("How it works", action: model.showTour).buttonStyle(.plain).font(.system(size: 10, design: .monospaced))
                }.padding(.top, 4)
            }
            Spacer(minLength: 0)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(RatioTheme.panel, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(RatioTheme.line))
    }
    private var activitySection: some View {
        VStack(spacing: 0) {
            HStack {
                Eyebrow(text: "Activity")
                Spacer()
                Picker("Filter activity", selection: $model.filter) {
                    Text("All activity").tag(AppModel.ActivityFilter.all)
                    Text("Unclassified (\(model.unclassifiedCount))").tag(AppModel.ActivityFilter.unclassified)
                }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Filter activity").frame(width: 278).controlSize(.small)
            }.padding(.bottom, 15)
            Hairline()
            if model.activityRows.isEmpty {
                VStack(spacing: 8) {
                    Text(model.filter == .unclassified ? "All caught up." : "No activity yet.").font(.system(size: 12, design: .monospaced))
                    Text(model.filter == .unclassified ? "Every tracked source has a category." : "Your real activity will appear here.")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 28)
            } else {
                ForEach(model.activityRows) { activity in
                    ActivityRow(activity: activity, isActive: activity.id == model.activeSource?.id && !model.session.isPaused) {
                        model.classify(activity.source, as: $0)
                    }
                    Hairline()
                }
            }
            HStack {
                Text("Unclassified time is excluded from your ratio.")
                Spacer()
                if model.unclassifiedCount > 0 { Text("\(ActivityFormatting.duration(model.summary.unclassifiedSeconds)) unclassified").foregroundStyle(RatioTheme.unknown) }
            }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).padding(.top, 13)
        }
    }
}

struct RatioSummaryView: View {
    let summary: DaySummary
    var compact = false
    private var create: String { ActivityFormatting.percentage(summary.createPercentage) }
    private var consume: String { ActivityFormatting.percentage(summary.createPercentage.map { 100 - $0 }) }
    var body: some View {
        VStack(spacing: compact ? 16 : 23) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                number(create, category: .create)
                Spacer(minLength: 12)
                Text(":").font(.system(size: compact ? 32 : 52, weight: .ultraLight, design: .monospaced)).foregroundStyle(.tertiary)
                Spacer(minLength: 12)
                number(consume, category: .consume)
            }
            GeometryReader { geometry in
                HStack(spacing: 3) {
                    if let percentage = summary.createPercentage {
                        if percentage > 0 { Rectangle().fill(RatioTheme.create).frame(width: max(0, (geometry.size.width - (percentage < 100 ? 3 : 0)) * percentage / 100)) }
                        if percentage < 100 { Rectangle().fill(RatioTheme.consume) }
                    } else { Rectangle().fill(RatioTheme.line) }
                }
            }.frame(height: compact ? 4 : 6).clipShape(Capsule())
            HStack {
                Label(ActivityFormatting.duration(summary.createSeconds) + " creating", systemImage: "arrow.up.right")
                    .foregroundStyle(RatioTheme.create)
                Spacer()
                Label(ActivityFormatting.duration(summary.consumeSeconds) + " consuming", systemImage: "arrow.down.right")
                    .foregroundStyle(RatioTheme.consume)
            }.font(.system(size: compact ? 9 : 10, design: .monospaced))
        }.padding(compact ? 0 : 24)
            .background(compact ? Color.clear : RatioTheme.panel, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(compact ? Color.clear : RatioTheme.line))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(summary.createPercentage == nil ? "No classified time. Ratio is undefined." : "\(create) percent create, \(consume) percent consume")
    }
    private func number(_ value: String, category: ActivityCategory) -> some View {
        VStack(alignment: category == .create ? .leading : .trailing, spacing: compact ? 4 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: compact ? 46 : 76, weight: .light, design: .monospaced)).tracking(-4).monospacedDigit()
                if summary.createPercentage != nil { Text("%").font(.system(size: compact ? 14 : 21, weight: .light, design: .monospaced)).foregroundStyle(RatioTheme.category(category).opacity(0.65)) }
            }
            Text(category.title.uppercased()).font(.system(size: compact ? 9 : 10, weight: .medium, design: .monospaced)).tracking(2)
        }.foregroundStyle(RatioTheme.category(category))
    }
}

struct ActivityRow: View {
    let activity: ActivityTotal
    var isActive = false
    let classify: (ActivityCategory?) -> Void
    var body: some View {
        HStack(spacing: 11) {
            SourceIcon(source: activity.source)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(activity.source.name).font(.system(size: 11, weight: .medium, design: .monospaced)).lineLimit(1)
                    if isActive { Text("NOW").font(.system(size: 7, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(RatioTheme.create) }
                }
                Text(activity.source.kind == .website ? "Website" : "Application").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(ActivityFormatting.duration(activity.seconds)).font(.system(size: 11, design: .monospaced)).monospacedDigit().foregroundStyle(.secondary).padding(.trailing, 14)
            CategoryPicker(source: activity.source, category: activity.category, classify: classify)
        }.padding(.vertical, 11).padding(.horizontal, 2)
            .accessibilityElement(children: .contain)
    }
}
