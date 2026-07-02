import SwiftUI
import Charts

/// Shared chart view used by both the widget and the host-app window.
public struct PriceChartView: View {
    let snapshot: PriceSnapshot
    let hoursBack: Int
    let hoursFwd: Int

    public init(snapshot: PriceSnapshot, hoursBack: Int = 8, hoursFwd: Int = 10) {
        self.snapshot = snapshot
        self.hoursBack = hoursBack
        self.hoursFwd = hoursFwd
    }

    private var nowHour: Date { Calendar.central.startOfHour(snapshot.asOf) }

    private var window: [PricePoint] {
        let cal = Calendar.central
        let lo = cal.date(byAdding: .hour, value: -hoursBack, to: nowHour)!
        let hi = cal.date(byAdding: .hour, value: hoursFwd, to: nowHour)!
        return snapshot.points.filter { $0.hour >= lo && $0.hour <= hi }
    }

    public var body: some View {
        Chart(window) { p in
            BarMark(
                x: .value("Hour", p.hour, unit: .hour),
                y: .value("Price", p.cents)
            )
            .foregroundStyle(PriceLevel.color(p.cents))
            .opacity(p.predicted ? 0.40 : 1.0)
            .cornerRadius(2)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                if let d = value.as(Date.self) {
                    AxisValueLabel {
                        Text(d, format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)).locale(Locale(identifier: "en_US")))
                            .font(.system(size: 8))
                    }
                    AxisGridLine()
                    AxisTick()
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                if let v = value.as(Double.self) {
                    AxisValueLabel { Text("\(Int(v))¢").font(.system(size: 8)) }
                    AxisGridLine()
                }
            }
        }
        // Mark "now" with a rule.
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plot = proxy.plotFrame,
                   let x = proxy.position(forX: nowHour) {
                    let rect = geo[plot]
                    Path { p in
                        p.move(to: CGPoint(x: rect.minX + x, y: rect.minY))
                        p.addLine(to: CGPoint(x: rect.minX + x, y: rect.maxY))
                    }
                    .stroke(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
        }
    }
}

/// The full widget content: headline number + chart.
public struct PriceWidgetView: View {
    let snapshot: PriceSnapshot
    let hoursBack: Int
    let hoursFwd: Int
    let compact: Bool

    public init(snapshot: PriceSnapshot, hoursBack: Int, hoursFwd: Int, compact: Bool = false) {
        self.snapshot = snapshot
        self.hoursBack = hoursBack
        self.hoursFwd = hoursFwd
        self.compact = compact
    }

    private var color: Color { PriceLevel.color(snapshot.current) }

    public var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(snapshot.current.centsString)¢")
                    .font(.system(size: compact ? 34 : 40, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                VStack(alignment: .leading, spacing: 0) {
                    Text("per kWh").font(.caption2).foregroundStyle(.secondary)
                    Text(updatedString).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if !compact {
                    Text("ComEd").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            if !compact {
                PriceChartView(snapshot: snapshot, hoursBack: hoursBack, hoursFwd: hoursFwd)
            }
        }
        .padding(compact ? 8 : 12)
    }

    private var updatedString: String {
        let f = DateFormatter()
        f.timeZone = .central
        f.dateFormat = "h:mm a"
        let base = "as of \(f.string(from: snapshot.asOf)) CT"
        return snapshot.stale ? "\(base) (stale)" : base
    }
}
