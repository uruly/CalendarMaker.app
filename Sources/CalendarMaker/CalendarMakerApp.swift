import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

private enum Layout {
    static let page = CGSize(width: 595.28, height: 841.89) // A4 at 72 dpi
    static let margin: CGFloat = 20
}

private struct Month: Equatable {
    var year: Int
    var month: Int

    init(date: Date = .now) {
        let parts = Calendar.japaneseGregorian.dateComponents([.year, .month], from: date)
        year = parts.year ?? 2026
        month = parts.month ?? 1
    }

    func adding(_ value: Int) -> Month {
        let total = year * 12 + month - 1 + value
        return Month(year: total / 12, month: total % 12 + 1)
    }

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    var title: String { "\(year)年 \(month)月" }

    func days(firstWeekday: Int) -> [Int?] {
        let calendar = Calendar.japaneseGregorian
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let offset = (calendar.component(.weekday, from: first) - firstWeekday + 7) % 7
        return Array(repeating: nil, count: offset) + range.map(Optional.some)
    }

    func key(for day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

private extension Calendar {
    static var japaneseGregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }
}

private struct Holidays {
    static let shared = Holidays()
    private let names: [String: String]

    init() {
        guard let url = Bundle.main.url(forResource: "holidays", withExtension: "csv")
                ?? Bundle.module.url(forResource: "holidays", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            names = [:]
            return
        }
        names = Dictionary(uniqueKeysWithValues: text.split(whereSeparator: \.isNewline).dropFirst().compactMap { row in
            let fields = row.split(separator: ",", maxSplits: 1).map(String.init)
            return fields.count == 2 ? (fields[0], fields[1]) : nil
        })
    }

    func name(month: Month, day: Int) -> String? { names[month.key(for: day)] }
    func hasCoverage(year: Int) -> Bool { (2026...2027).contains(year) && !names.isEmpty }
}

private enum TextWeight: String, CaseIterable, Identifiable {
    case regular = "標準"
    case medium = "中"
    case semibold = "やや太い"
    case bold = "太い"

    var id: String { rawValue }
    var fontWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

private enum CalendarTemplate: String, CaseIterable, Identifiable {
    case classic = "エディトリアル"
    case gallery = "フォト"
    case modern = "ミニマル"
    case pop = "ポップ"

    var id: String { rawValue }
    var photoSize: CGSize {
        switch self {
        case .classic: CGSize(width: 361, height: 304)
        case .gallery: CGSize(width: 555, height: 230)
        case .modern: CGSize(width: 354, height: 324)
        case .pop: CGSize(width: 555, height: 286)
        }
    }
    var description: String {
        switch self {
        case .classic: "写真と文字を組み合わせた誌面風レイアウト"
        case .gallery: "横長の写真を主役にしたレイアウト"
        case .modern: "余白と罫線を生かしたレイアウト"
        case .pop: "明るい色と丸みのある文字のレイアウト"
        }
    }
}

private struct Typography {
    let scale: Double
    let weight: TextWeight
    let monthFamily: String
    let dayFamily: String

    func font(size: CGFloat, family: String, design: Font.Design = .default) -> Font {
        let pointSize = size * scale
        return (family.isEmpty ? Font.system(size: pointSize, design: design) : Font.custom(family, size: pointSize))
            .weight(weight.fontWeight)
    }

    func month(_ size: CGFloat, design: Font.Design = .default) -> Font {
        font(size: size, family: monthFamily, design: design)
    }
    func day(_ size: CGFloat, design: Font.Design = .default) -> Font {
        font(size: size, family: dayFamily, design: design)
    }
}

@MainActor
private final class EditorModel: ObservableObject {
    @Published var selectedMonth = Month()
    @Published var template: CalendarTemplate = .classic
    @Published var mainColor = Color(red: 0.16, green: 0.25, blue: 0.32)
    @Published var showLastMonth = true
    @Published var showNextMonth = true
    @Published var image: NSImage?
    @Published var printError: String?
    var originalImage: NSImage?
    var cropSettings = CropSettings()
    var cropTemplate: CalendarTemplate?
    @Published var fontScale = 1.2
    @Published var fontWeight: TextWeight = .semibold
    @Published var monthFontFamily = ""
    @Published var dayFontFamily = ""
    @Published var firstWeekday: Int {
        didSet { UserDefaults.standard.set(firstWeekday, forKey: "firstWeekday") }
    }

    init() {
        let saved = UserDefaults.standard.integer(forKey: "firstWeekday")
        firstWeekday = saved == 2 ? 2 : 1
    }

    func printPage() {
        let renderer = ImageRenderer(content: CalendarPage(
            month: selectedMonth,
            template: template,
            firstWeekday: firstWeekday,
            mainColor: mainColor,
            showLastMonth: showLastMonth,
            showNextMonth: showNextMonth,
            image: image,
            typography: typography
        ))
        renderer.proposedSize = ProposedViewSize(Layout.page)
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData) else {
            printError = "印刷用の紙面を作成できませんでした。"
            return
        }
        var mediaBox = CGRect(origin: .zero, size: Layout.page)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            printError = "印刷用の紙面を作成できませんでした。"
            return
        }
        context.beginPDFPage(nil)
        renderer.render { _, draw in
            draw(context)
        }
        context.endPDFPage()
        context.closePDF()
        guard let document = PDFDocument(data: pdfData as Data), document.pageCount == 1 else {
            printError = "印刷用の紙面を作成できませんでした。"
            return
        }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = Layout.page
        info.orientation = .portrait
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        guard let operation = document.printOperation(for: info, scalingMode: .pageScaleNone, autoRotate: false) else {
            printError = "印刷ダイアログを開けませんでした。"
            return
        }
        operation.jobTitle = "カレンダー \(selectedMonth.title)"
        operation.showsPrintPanel = true
        operation.run()
    }

    var typography: Typography {
        Typography(scale: fontScale, weight: fontWeight,
                   monthFamily: monthFontFamily, dayFamily: dayFontFamily)
    }
}

private struct Palette {
    let main: Color
    let pale: Color
    let border: Color
    let bar: Color
    let pageBackground: Color
    let saturday: Color
    let sunday: Color
    let popAccent: Color
    let popCard: Color
    let popSunday: Color
    let popSaturday: Color
    let popPaper = Color(red: 1, green: 0.993, blue: 0.975)
    let ink = Color(white: 0.16)

    init(main: Color) {
        let color = NSColor(main).usingColorSpace(.deviceRGB) ?? .systemBlue
        self.main = Color(NSColor(calibratedHue: color.hueComponent,
                                  saturation: max(0.28, color.saturationComponent * 0.85),
                                  brightness: min(0.52, color.brightnessComponent), alpha: 1))
        pale = Color(NSColor(calibratedHue: color.hueComponent,
                             saturation: max(0.035, color.saturationComponent * 0.13),
                             brightness: 0.97, alpha: 1))
        border = Color(NSColor(calibratedHue: color.hueComponent,
                               saturation: max(0.04, color.saturationComponent * 0.15),
                               brightness: 0.82, alpha: 1))
        bar = Color(NSColor(calibratedHue: color.hueComponent,
                            saturation: max(0.035, color.saturationComponent * 0.10),
                            brightness: 0.985, alpha: 1))
        pageBackground = Color(NSColor(calibratedHue: color.hueComponent,
                                       saturation: 0.012, brightness: 0.995, alpha: 1))
        saturday = Color(red: 0.36, green: 0.48, blue: 0.57)
        sunday = Color(red: 0.66, green: 0.30, blue: 0.31)
        popAccent = Color(NSColor(calibratedHue: color.hueComponent,
                                  saturation: 0.62, brightness: 0.82, alpha: 1))
        popCard = Color(NSColor(calibratedHue: color.hueComponent,
                                saturation: 0.04, brightness: 0.995, alpha: 1))
        popSunday = Color(red: 1, green: 0.93, blue: 0.90)
        popSaturday = Color(red: 0.91, green: 0.96, blue: 1)
    }
}

private struct CalendarPage: View {
    let month: Month
    let template: CalendarTemplate
    let firstWeekday: Int
    let mainColor: Color
    let showLastMonth: Bool
    let showNextMonth: Bool
    let image: NSImage?
    let typography: Typography

    private var palette: Palette { Palette(main: mainColor) }
    private var weekdays: [String] {
        firstWeekday == 2 ? ["月", "火", "水", "木", "金", "土", "日"] : ["日", "月", "火", "水", "木", "金", "土"]
    }
    private var monthDesign: Font.Design {
        template == .modern || template == .pop ? .rounded : .serif
    }
    private var calendarWidth: CGFloat { Layout.page.width - Layout.margin * 2 }
    private var calendarSpacing: CGFloat { template == .pop ? 4 : 0 }
    private var columnWidth: CGFloat { (calendarWidth - calendarSpacing * 6) / 7 }

    var body: some View {
        VStack(spacing: 0) {
            topStage
            HStack(spacing: calendarSpacing) {
                ForEach(0..<7, id: \.self) { index in
                    Text(weekdays[index])
                        .font(typography.day(template == .pop ? 10 : 9, design: .rounded))
                        .foregroundStyle(weekdayHeaderForeground(column: index))
                        .frame(width: columnWidth, height: 30)
                        .background {
                            if template == .pop {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(weekdayHeaderBackground(column: index))
                            } else {
                                Rectangle().fill(weekdayHeaderBackground(column: index))
                            }
                        }
                }
            }
            .frame(width: calendarWidth, height: 30)
            .background(template == .gallery ? palette.bar : template == .pop ? palette.popPaper : .white)
            .overlay(alignment: .top) {
                if template != .pop { palette.main.frame(height: 1.5) }
            }
            .overlay(alignment: .bottom) {
                if template != .pop { palette.border.frame(height: 0.5) }
            }
            calendarGrid
        }
        .padding(.horizontal, Layout.margin)
        .padding(.top, 18)
        .frame(width: Layout.page.width, height: Layout.page.height)
        .background(template == .pop ? palette.popPaper : palette.pageBackground)
        .environment(\.colorScheme, .light)
    }

    private var topStage: some View {
        Group {
            switch template {
            case .classic: classicTopStage
            case .gallery: galleryTopStage
            case .modern: modernTopStage
            case .pop: popTopStage
            }
        }
        .frame(width: Layout.page.width - Layout.margin * 2, height: 370, alignment: .topLeading)
    }

    private var classicTopStage: some View {
        ZStack(alignment: .topLeading) {
            Text("CALENDAR  /  " + String(month.year))
                .font(typography.month(9, design: .monospaced))
                .tracking(2)
                .foregroundStyle(palette.main)
                .offset(x: 10, y: 9)

            VStack(spacing: 12) {
                if showLastMonth { miniCalendar(month.adding(-1), height: 132) }
                if showNextMonth { miniCalendar(month.adding(1), height: 132) }
            }
            .frame(width: 165, height: 290, alignment: .top)
            .offset(x: 10, y: 41)

            photo()
                .offset(x: 194, y: 26)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(String(month.year))
                    .font(typography.month(16, design: monthDesign))
                    .lineLimit(1)
                Text("\(month.month)月")
                    .font(typography.month(43, design: monthDesign))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(palette.main)
            .padding(.horizontal, 16)
            .frame(height: 72)
            .background(.white)
            .offset(x: 210, y: 256)
        }
    }

    private var galleryTopStage: some View {
        ZStack(alignment: .topLeading) {
            Text(String(month.year) + "  /  MONTHLY CALENDAR")
                .font(typography.month(9, design: .monospaced))
                .tracking(1.7)
                .foregroundStyle(palette.main)
                .offset(x: 2, y: 5)

            photo()
                .offset(y: 24)

            VStack(alignment: .leading, spacing: 0) {
                Text(String(month.year))
                    .font(typography.month(14, design: monthDesign))
                Text("\(month.month)月")
                    .font(typography.month(47, design: monthDesign))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(palette.main)
            .padding(.horizontal, 20)
            .frame(width: 190, height: 104, alignment: .leading)
            .background(.white)
            .offset(x: 20, y: 150)

            HStack(alignment: .top, spacing: 14) {
                if showLastMonth { miniCalendar(month.adding(-1), height: 96) }
                if showNextMonth { miniCalendar(month.adding(1), height: 96) }
            }
            .frame(width: 555, height: 96, alignment: .trailing)
            .offset(y: 267)
        }
    }

    private var modernTopStage: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(month.year))
                    .font(typography.month(14, design: .monospaced))
                    .tracking(2)
                Text("\(month.month)月")
                    .font(typography.month(57, design: monthDesign))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Rectangle()
                    .fill(palette.main)
                    .frame(height: 1.5)
                    .padding(.top, 10)
            }
            .foregroundStyle(palette.main)
            .frame(width: 165, height: 130, alignment: .topLeading)
            .offset(x: 10, y: 13)

            VStack(spacing: 11) {
                if showLastMonth { miniCalendar(month.adding(-1), height: 100) }
                if showNextMonth { miniCalendar(month.adding(1), height: 100) }
            }
            .frame(width: 165, height: 215, alignment: .top)
            .offset(x: 10, y: 143)

            photo()
                .offset(x: 201, y: 18)
        }
    }

    private var popTopStage: some View {
        ZStack(alignment: .topLeading) {
            photo()
                .clipShape(RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 4) {
                Text(String(month.year))
                    .font(typography.month(15, design: .rounded))
                Text("\(month.month)月")
                    .font(typography.month(58, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                Text("MONTHLY CALENDAR")
                    .font(typography.month(7, design: .rounded))
                    .tracking(1.5)
            }
            .foregroundStyle(.white)
            .padding(17)
            .frame(width: 230, height: 153, alignment: .topLeading)
            .background(palette.popAccent, in: RoundedRectangle(cornerRadius: 15))
            .offset(x: 19, y: 19)

            if showLastMonth {
                miniCalendar(month.adding(-1), height: 103)
                    .offset(x: 23, y: 237)
            }
            if showNextMonth {
                miniCalendar(month.adding(1), height: 103)
                    .offset(x: 382, y: 251)
            }
        }
    }

    private func photo() -> some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                palette.pale
            }
        }
        .frame(width: template.photoSize.width, height: template.photoSize.height)
        .clipped()
    }

    private var calendarGrid: some View {
        let slots = daySlots()
        let rows = slots.count / 7
        let rowHeight = (405 - calendarSpacing * CGFloat(rows - 1)) / CGFloat(rows)
        return VStack(spacing: calendarSpacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: calendarSpacing) {
                    ForEach(0..<7, id: \.self) { column in
                        let slot = slots[row * 7 + column]
                        ZStack(alignment: .top) {
                            if template == .pop {
                                RoundedRectangle(cornerRadius: 9).fill(popDayBackground(column: column))
                            } else {
                                (template == .gallery && (column == 0 || column == 6) ? palette.bar : .white)
                            }
                            Text(String(slot.day))
                                .font(typography.day(template == .pop ? 21 : 17, design: .rounded))
                                .foregroundStyle(dayColor(slot, column: column))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(width: columnWidth, alignment: .center)
                                .padding(.top, template == .pop ? 13 : 10)
                        }
                        .frame(width: columnWidth, height: rowHeight)
                        .overlay {
                            if template == .pop {
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(palette.popAccent.opacity(0.14), lineWidth: 0.6)
                            }
                        }
                        .accessibilityLabel("\(slot.month.title) \(slot.day)日\(slot.isCurrent ? "" : "（隣月）")")
                    }
                }
            }
        }
        .frame(width: calendarWidth, height: 405)
        .overlay {
            if template != .pop {
                GeometryReader { geometry in
                    Path { path in
                        for column in 0...7 {
                            let x = geometry.size.width * CGFloat(column) / 7
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                        }
                        for row in 0...rows {
                            let y = geometry.size.height * CGFloat(row) / CGFloat(rows)
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                    }
                    .stroke(palette.main.opacity(0.38), lineWidth: 0.9)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private struct DaySlot {
        let month: Month
        let day: Int
        let isCurrent: Bool
    }

    private func daySlots() -> [DaySlot] {
        let monthDays = month.days(firstWeekday: firstWeekday)
        let leading = monthDays.prefix(while: { $0 == nil }).count
        let currentCount = monthDays.count - leading
        let rows = max(5, Int(ceil(Double(monthDays.count) / 7)))
        let previousMonth = month.adding(-1)
        let previousCount = previousMonth.days(firstWeekday: firstWeekday).compactMap { $0 }.count
        return (0..<(rows * 7)).map { index in
            if index < leading {
                return DaySlot(month: previousMonth, day: previousCount - leading + index + 1, isCurrent: false)
            }
            if index < leading + currentCount {
                return DaySlot(month: month, day: index - leading + 1, isCurrent: true)
            }
            return DaySlot(month: month.adding(1), day: index - leading - currentCount + 1, isCurrent: false)
        }
    }

    private func dayColor(_ slot: DaySlot, column: Int) -> Color {
        if Holidays.shared.name(month: slot.month, day: slot.day) != nil { return palette.sunday }
        if !slot.isCurrent { return Color(white: template == .pop ? 0.60 : 0.70) }
        let sunday = firstWeekday == 1 ? 0 : 6
        let saturday = firstWeekday == 1 ? 6 : 5
        if column == sunday { return palette.sunday }
        if column == saturday { return palette.saturday }
        return template == .pop ? palette.main : palette.ink
    }

    private func popDayBackground(column: Int) -> Color {
        if column == (firstWeekday == 1 ? 0 : 6) { return palette.popSunday }
        if column == (firstWeekday == 1 ? 6 : 5) { return palette.popSaturday }
        return palette.popCard
    }

    private func weekdayHeaderBackground(column: Int) -> Color {
        if column == (firstWeekday == 1 ? 0 : 6) { return palette.popSunday }
        if column == (firstWeekday == 1 ? 6 : 5) { return palette.popSaturday }
        if template == .pop { return palette.popAccent }
        return template == .gallery ? palette.bar : .white
    }

    private func weekdayHeaderForeground(column: Int) -> Color {
        if column == (firstWeekday == 1 ? 0 : 6) { return palette.sunday }
        if column == (firstWeekday == 1 ? 6 : 5) { return palette.saturday }
        return template == .pop ? .white : palette.ink
    }

    private func miniCalendar(_ target: Month, height: CGFloat = 150) -> some View {
        let days = target.days(firstWeekday: firstWeekday)
        let rows = Int(ceil(Double(days.count) / 7))
        let compact = height < 125
        return VStack(alignment: .leading, spacing: compact ? 1 : 2) {
            Text("\(target.month)月")
                .font(typography.month(compact ? 9 : 11, design: monthDesign))
                .foregroundStyle(palette.main)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { column, label in
                    Text(label)
                        .foregroundStyle(weekdayColor(column: column))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: compact ? 10 : 14)
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let index = row * 7 + column
                        Text(index < days.count ? days[index].map(String.init) ?? "" : "")
                            .foregroundStyle(miniDayColor(month: target, day: index < days.count ? days[index] : nil,
                                                          column: column))
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(height: compact ? 10 : 14)
            }
            Spacer(minLength: 0)
        }
        .font(typography.day(compact ? 6.5 : 7.5, design: .rounded))
        .padding(compact ? 6 : 8)
        .frame(width: 165, height: height)
        .background(.white, in: RoundedRectangle(cornerRadius: template == .pop ? 10 : 0))
        .overlay {
            if template == .pop {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(palette.popAccent.opacity(0.25), lineWidth: 1)
            }
        }
        .overlay(alignment: .top) {
            if template != .pop { palette.main.frame(height: 1) }
        }
        .overlay(alignment: .bottom) {
            if template != .pop { palette.border.frame(height: 0.5) }
        }
    }

    private func weekdayColor(column: Int) -> Color {
        if column == (firstWeekday == 1 ? 0 : 6) { return palette.sunday }
        if column == (firstWeekday == 1 ? 6 : 5) { return palette.saturday }
        return palette.ink
    }

    private func miniDayColor(month: Month, day: Int?, column: Int) -> Color {
        if let day, Holidays.shared.name(month: month, day: day) != nil { return palette.sunday }
        return weekdayColor(column: column)
    }
}

private struct EditorView: View {
    private struct ImageEditorSession: Identifiable {
        let id = UUID()
        let source: NSImage
        let settings: CropSettings
        let template: CalendarTemplate
    }

    @ObservedObject var model: EditorModel
    @State private var choosingImage = false
    @State private var imageEditorSession: ImageEditorSession?
    @State private var imageError: String?

    var body: some View {
        HSplitView {
            Form {
                Section("テンプレート") {
                    Picker("デザイン", selection: $model.template) {
                        ForEach(CalendarTemplate.allCases) { template in
                            Text(template.rawValue).tag(template)
                        }
                    }
                    Text(model.template.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("対象年月") {
                    Picker("年", selection: Binding(
                        get: { model.selectedMonth.year },
                        set: { model.selectedMonth = Month(year: $0, month: model.selectedMonth.month) }
                    )) {
                        ForEach(1900...2100, id: \.self) { year in
                            Text("\(year)年").tag(year)
                        }
                    }
                    Picker("月", selection: Binding(
                        get: { model.selectedMonth.month },
                        set: { model.selectedMonth = Month(year: model.selectedMonth.year, month: $0) }
                    )) {
                        ForEach(1...12, id: \.self) { month in
                            Text("\(month)月").tag(month)
                        }
                    }
                    HStack {
                        Button("前月") { model.selectedMonth = model.selectedMonth.adding(-1) }
                        Spacer()
                        Text(model.selectedMonth.title)
                            .font(.headline)
                        Spacer()
                        Button("翌月") { model.selectedMonth = model.selectedMonth.adding(1) }
                    }
                    Button("今月に戻る") { model.selectedMonth = Month() }
                }
                Section("表示") {
                    Picker("週の始まり", selection: $model.firstWeekday) {
                        Text("月曜日").tag(2)
                        Text("日曜日").tag(1)
                    }
                    Toggle("先月を表示", isOn: $model.showLastMonth)
                    Toggle("翌月を表示", isOn: $model.showNextMonth)
                }
                Section("配色") {
                    ColorPicker("メインカラー", selection: $model.mainColor, supportsOpacity: false)
                    HStack {
                        Circle().fill(model.mainColor)
                        Circle().fill(Palette(main: model.mainColor).pale)
                        Circle().fill(Palette(main: model.mainColor).border)
                    }
                    .frame(height: 22)
                    .accessibilityLabel("推奨カラーセット")
                }
                Section("文字") {
                    HStack {
                        Slider(value: $model.fontScale, in: 1.0...1.5, step: 0.05) {
                            Text("全体の文字サイズ")
                        }
                        Text("\(Int(model.fontScale * 100))%")
                            .monospacedDigit()
                    }
                    Picker("全体の太さ", selection: $model.fontWeight) {
                        ForEach(TextWeight.allCases) { weight in
                            Text(weight.rawValue).tag(weight)
                        }
                    }
                    Picker("年月のフォント", selection: $model.monthFontFamily) {
                        Text("システム").tag("")
                        ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    Picker("カレンダー内の日付のフォント", selection: $model.dayFontFamily) {
                        Text("システム").tag("")
                        ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                }
                Section("アイキャッチ画像") {
                    Button(model.image == nil ? "画像を選ぶ…" : "画像を変更…") { choosingImage = true }
                    Button("画像を編集…") {
                        guard let source = model.originalImage ?? model.image else { return }
                        let settings = model.cropTemplate == model.template ? model.cropSettings : CropSettings()
                        imageEditorSession = ImageEditorSession(
                            source: source, settings: settings, template: model.template
                        )
                    }
                    .disabled(model.image == nil)
                    if model.image != nil {
                        Button("画像を削除") {
                            model.image = nil
                            model.originalImage = nil
                            model.cropSettings = CropSettings()
                            model.cropTemplate = nil
                        }
                    }
                }
                if !Holidays.shared.hasCoverage(year: model.selectedMonth.year) {
                    Text("\(model.selectedMonth.year)年の祝日は未収録です。")
                        .foregroundStyle(.secondary)
                }
                Button("プリント…") { model.printPage() }
            }
            .formStyle(.grouped)
            .frame(minWidth: 250, idealWidth: 290, maxWidth: 340)

            GeometryReader { geometry in
                let scale = max(0.1, min(1, (geometry.size.width - 40) / Layout.page.width,
                                         (geometry.size.height - 40) / Layout.page.height))
                CalendarPage(
                    month: model.selectedMonth,
                    template: model.template,
                    firstWeekday: model.firstWeekday,
                    mainColor: model.mainColor,
                    showLastMonth: model.showLastMonth,
                    showNextMonth: model.showNextMonth,
                    image: model.image,
                    typography: model.typography
                )
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: Layout.page.width * scale, height: Layout.page.height * scale,
                       alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 850, minHeight: 650)
        .fileImporter(isPresented: $choosingImage, allowedContentTypes: [.image]) { result in
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                guard let image = NSImage(contentsOf: url) else {
                    imageError = "画像を読み込めませんでした。"
                    return
                }
                DispatchQueue.main.async {
                    imageEditorSession = ImageEditorSession(
                        source: image, settings: CropSettings(), template: model.template
                    )
                }
            } catch {
                imageError = error.localizedDescription
            }
        }
        .sheet(item: $imageEditorSession) { session in
            ImageCropEditor(
                source: session.source,
                initial: session.settings,
                photoSize: session.template.photoSize,
                templateName: session.template.rawValue,
                pagePreview: { cropped in
                    AnyView(CalendarPage(
                        month: model.selectedMonth,
                        template: session.template,
                        firstWeekday: model.firstWeekday,
                        mainColor: model.mainColor,
                        showLastMonth: model.showLastMonth,
                        showNextMonth: model.showNextMonth,
                        image: cropped,
                        typography: model.typography
                    ))
                }
            ) { cropped, settings in
                model.originalImage = session.source
                model.cropSettings = settings
                model.cropTemplate = session.template
                model.image = cropped
            }
        }
        .alert("画像エラー", isPresented: Binding(get: { imageError != nil }, set: { if !$0 { imageError = nil } })) {
            Button("OK") { imageError = nil }
        } message: {
            Text(imageError ?? "")
        }
        .alert("印刷エラー", isPresented: Binding(get: { model.printError != nil }, set: { if !$0 { model.printError = nil } })) {
            Button("OK") { model.printError = nil }
        } message: {
            Text(model.printError ?? "")
        }
    }
}

@main
private struct CalendarMakerApp: App {
    @StateObject private var model = EditorModel()

    var body: some Scene {
        WindowGroup("カレンダーメーカー") {
            EditorView(model: model)
        }
        Settings {
            Form {
                Picker("週の始まり", selection: $model.firstWeekday) {
                    Text("月曜日").tag(2)
                    Text("日曜日").tag(1)
                }
            }
            .padding()
            .frame(width: 320)
        }
        .commands {
            CommandGroup(replacing: .printItem) {
                Button("プリント…") { model.printPage() }
                    .keyboardShortcut("p")
            }
        }
    }
}
