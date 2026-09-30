import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum Layout {
    static let page = CGSize(width: 595.28, height: 841.89) // A4 at 72 dpi
    static let margin: CGFloat = 30
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

private struct Typography {
    let scale: Double
    let weight: TextWeight
    let monthFamily: String
    let dayFamily: String

    func font(size: CGFloat, family: String) -> Font {
        let pointSize = size * scale
        return (family.isEmpty ? Font.system(size: pointSize) : Font.custom(family, size: pointSize))
            .weight(weight.fontWeight)
    }

    func month(_ size: CGFloat) -> Font { font(size: size, family: monthFamily) }
    func day(_ size: CGFloat) -> Font { font(size: size, family: dayFamily) }
}

@MainActor
private final class EditorModel: ObservableObject {
    @Published var selectedMonth = Month()
    @Published var mainColor = Color(red: 0.18, green: 0.40, blue: 0.62)
    @Published var showLastMonth = true
    @Published var showTwoMonthsAgo = false
    @Published var image: NSImage?
    @Published var fontScale = 1.2
    @Published var fontWeight: TextWeight = .semibold
    @Published var monthFontFamily = ""
    @Published var dayFontFamily = ""
    @Published var firstWeekday: Int {
        didSet { UserDefaults.standard.set(firstWeekday, forKey: "firstWeekday") }
    }

    init() {
        let saved = UserDefaults.standard.integer(forKey: "firstWeekday")
        firstWeekday = saved == 1 ? 1 : 2
    }

    func printPage() {
        let view = NSHostingView(rootView: CalendarPage(
            month: selectedMonth,
            firstWeekday: firstWeekday,
            mainColor: mainColor,
            showLastMonth: showLastMonth,
            showTwoMonthsAgo: showTwoMonthsAgo,
            image: image,
            typography: typography
        ))
        view.frame = CGRect(origin: .zero, size: Layout.page)
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = Layout.page
        info.orientation = .portrait
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        let operation = NSPrintOperation(view: view, printInfo: info)
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

    init(main: Color) {
        self.main = main
        let color = NSColor(main).usingColorSpace(.deviceRGB) ?? .systemBlue
        pale = Color(NSColor(calibratedHue: color.hueComponent,
                             saturation: max(0.06, color.saturationComponent * 0.20),
                             brightness: 0.96, alpha: 1))
        border = Color(NSColor(calibratedHue: color.hueComponent,
                               saturation: max(0.08, color.saturationComponent * 0.28),
                               brightness: 0.76, alpha: 1))
    }
}

private struct CalendarPage: View {
    let month: Month
    let firstWeekday: Int
    let mainColor: Color
    let showLastMonth: Bool
    let showTwoMonthsAgo: Bool
    let image: NSImage?
    let typography: Typography

    private var palette: Palette { Palette(main: mainColor) }
    private var headerHeight: CGFloat { 225 + (typography.scale - 1.2) * 180 }
    private var gridHeight: CGFloat { 470 - (typography.scale - 1.2) * 180 }
    private var weekdays: [String] {
        firstWeekday == 2 ? ["月", "火", "水", "木", "金", "土", "日"] : ["日", "月", "火", "水", "木", "金", "土"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: headerHeight)
            HStack(spacing: 0) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(typography.day(12))
                        .foregroundStyle(weekdayColor(index: index))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 28)
            .background(palette.pale)

            let days = month.days(firstWeekday: firstWeekday)
            let rows = max(5, Int(ceil(Double(days.count) / 7)))
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            let index = row * 7 + column
                            dayCell(index < days.count ? days[index] : nil, column: column)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .overlay(Rectangle().stroke(palette.border, lineWidth: 0.35))
                        }
                    }
                }
            }
            .frame(height: gridHeight)
            .overlay(Rectangle().stroke(palette.border, lineWidth: 0.7))
            Spacer(minLength: 0)
            Text("祝日: 内閣府公表データ（2026–2027年）")
                .font(typography.day(7))
                .foregroundStyle(.secondary)
        }
        .padding(Layout.margin)
        .frame(width: Layout.page.width, height: Layout.page.height)
        .background(.white)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                if showLastMonth { miniCalendar(month.adding(-1)) }
                if showTwoMonthsAgo { miniCalendar(month.adding(-2)) }
                Spacer(minLength: 0)
            }
            .frame(width: 118, height: headerHeight - 7)

            ZStack(alignment: .bottomLeading) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 401, height: headerHeight - 7)
                        .clipped()
                } else {
                    palette.pale
                }
                LinearGradient(colors: [.clear, .black.opacity(image == nil ? 0.12 : 0.72)],
                               startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text(month.title)
                        .font(typography.month(27))
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    if !Holidays.shared.hasCoverage(year: month.year) {
                        Text("この年の祝日は未収録です")
                            .font(typography.month(9))
                    }
                }
                .foregroundStyle(image == nil ? Color.black : Color.white)
                .padding(14)
            }
            .frame(width: 401, height: headerHeight - 7)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    private func dayCell(_ day: Int?, column: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let day {
                Text("\(day)")
                    .font(typography.day(15))
                    .foregroundStyle(Holidays.shared.name(month: month, day: day) == nil ? weekdayColor(index: column) : .red)
                if let holiday = Holidays.shared.name(month: month, day: day) {
                    Text(holiday)
                        .font(typography.day(8))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .padding(.top, 4)
    }

    private func weekdayColor(index: Int) -> Color {
        let sunday = firstWeekday == 1 ? 0 : 6
        let saturday = firstWeekday == 1 ? 6 : 5
        if index == sunday { return .red }
        if index == saturday { return .blue }
        return .black
    }

    private func miniCalendar(_ target: Month) -> some View {
        let days = target.days(firstWeekday: firstWeekday)
        let rows = Int(ceil(Double(days.count) / 7))
        return VStack(alignment: .leading, spacing: 3) {
            Text(target.title)
                .font(typography.month(9))
                .foregroundStyle(palette.main)
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day).frame(width: 16.5)
                }
            }
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let index = row * 7 + column
                        Text(index < days.count ? days[index].map(String.init) ?? "" : "")
                            .frame(width: 16.5)
                    }
                }
            }
        }
        .font(typography.day(7))
    }
}

private struct EditorView: View {
    @ObservedObject var model: EditorModel
    @State private var choosingImage = false
    @State private var imageError: String?

    var body: some View {
        HSplitView {
            Form {
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
                    Toggle("先々月を表示", isOn: $model.showTwoMonthsAgo)
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
                    if model.image != nil {
                        Button("画像を削除") { model.image = nil }
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

            ScrollView([.horizontal, .vertical]) {
                CalendarPage(
                    month: model.selectedMonth,
                    firstWeekday: model.firstWeekday,
                    mainColor: model.mainColor,
                    showLastMonth: model.showLastMonth,
                    showTwoMonthsAgo: model.showTwoMonthsAgo,
                    image: model.image,
                    typography: model.typography
                )
                .shadow(color: .black.opacity(0.15), radius: 12, y: 3)
                .padding(30)
                .frame(maxWidth: .infinity)
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
                model.image = image
            } catch {
                imageError = error.localizedDescription
            }
        }
        .alert("画像エラー", isPresented: Binding(get: { imageError != nil }, set: { if !$0 { imageError = nil } })) {
            Button("OK") { imageError = nil }
        } message: {
            Text(imageError ?? "")
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
