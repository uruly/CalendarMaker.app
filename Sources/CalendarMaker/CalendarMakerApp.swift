import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum Layout {
    static let page = CGSize(width: 595.28, height: 841.89) // A4 at 72 dpi
    static let margin: CGFloat = 12
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
    case classic = "クラシック"
    case gallery = "ギャラリー"
    case modern = "モダン"

    var id: String { rawValue }
    var description: String {
        switch self {
        case .classic: "小さなカレンダーと写真を並べた標準デザイン"
        case .gallery: "写真を横いっぱいに使うデザイン"
        case .modern: "余白と大きな年月を生かしたデザイン"
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
    @Published var template: CalendarTemplate = .classic
    @Published var mainColor = Color(red: 0.35, green: 0.08, blue: 0.75)
    @Published var showLastMonth = true
    @Published var showNextMonth = true
    @Published var image: NSImage?
    var originalImage: NSImage?
    var cropSettings = CropSettings()
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
        let view = NSHostingView(rootView: CalendarPage(
            month: selectedMonth,
            template: template,
            firstWeekday: firstWeekday,
            mainColor: mainColor,
            showLastMonth: showLastMonth,
            showNextMonth: showNextMonth,
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
    let bar: Color
    let pageBackground: Color
    let saturday: Color

    init(main: Color) {
        let color = NSColor(main).usingColorSpace(.deviceRGB) ?? .systemBlue
        self.main = Color(NSColor(calibratedHue: color.hueComponent,
                                  saturation: max(0.55, color.saturationComponent),
                                  brightness: min(0.55, color.brightnessComponent), alpha: 1))
        pale = Color(NSColor(calibratedHue: color.hueComponent,
                             saturation: max(0.06, color.saturationComponent * 0.20),
                             brightness: 0.96, alpha: 1))
        border = Color(NSColor(calibratedHue: color.hueComponent,
                               saturation: max(0.08, color.saturationComponent * 0.28),
                               brightness: 0.76, alpha: 1))
        bar = Color(NSColor(calibratedHue: color.hueComponent,
                            saturation: min(0.8, max(0.45, color.saturationComponent * 0.75)),
                            brightness: 0.98, alpha: 1))
        pageBackground = Color(NSColor(calibratedHue: color.hueComponent,
                                       saturation: 0.035, brightness: 0.91, alpha: 1))
        saturday = Color(red: 0.35, green: 0.51, blue: 0.58)
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

    var body: some View {
        VStack(spacing: 2) {
            topStage
            HStack(spacing: 1.5) {
                ForEach(0..<7, id: \.self) { index in
                    Text(weekdays[index])
                        .font(typography.day(10))
                        .foregroundStyle(template == .modern ? .white : palette.main)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(template == .modern ? palette.main : palette.bar)
                }
            }
            .frame(height: 28)
            calendarGrid
        }
        .padding(.horizontal, Layout.margin)
        .padding(.top, 10)
        .frame(width: Layout.page.width, height: Layout.page.height)
        .background(template == .gallery ? .white : palette.pageBackground)
        .environment(\.colorScheme, .light)
    }

    private var topStage: some View {
        Group {
            switch template {
            case .classic: classicTopStage
            case .gallery: galleryTopStage
            case .modern: modernTopStage
            }
        }
        .frame(width: Layout.page.width - Layout.margin * 2, height: 370, alignment: .topLeading)
    }

    private var classicTopStage: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 16) {
                if showLastMonth { miniCalendar(month.adding(-1)) }
                if showNextMonth { miniCalendar(month.adding(1)) }
                Spacer(minLength: 0)
            }
            .frame(width: 165, height: 320, alignment: .top)
            .offset(x: 10, y: 37)

            photo(width: 377, height: 274)
            .overlay(Rectangle().stroke(palette.border.opacity(0.45), lineWidth: 0.5))
            .offset(x: 191, y: 54)

            VStack(spacing: 0) {
                Text(String(month.year))
                    .font(typography.month(20))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 11)
                Spacer(minLength: 0)
                Text(String(month.month))
                    .font(typography.month(63))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.bottom, 9)
            }
            .foregroundStyle(.white)
            .frame(width: 135, height: 135)
            .background(palette.main, in: RoundedRectangle(cornerRadius: 3))
            .offset(x: 438, y: 0)
        }
    }

    private var galleryTopStage: some View {
        ZStack(alignment: .topLeading) {
            photo(width: 571, height: 235)

            VStack(alignment: .leading, spacing: 0) {
                Text(String(month.year))
                    .font(typography.month(17))
                Text("\(month.month)月")
                    .font(typography.month(42))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 19)
            .frame(width: 190, height: 100, alignment: .leading)
            .background(palette.main)
            .offset(x: 18, y: 123)

            HStack(alignment: .top, spacing: 16) {
                if showLastMonth { miniCalendar(month.adding(-1), height: 108) }
                if showNextMonth { miniCalendar(month.adding(1), height: 108) }
            }
            .frame(width: 571, height: 108)
            .offset(y: 250)
        }
    }

    private var modernTopStage: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(month.year))
                    .font(typography.month(21))
                Text(String(month.month))
                    .font(typography.month(70))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Rectangle()
                    .fill(palette.main)
                    .frame(height: 4)
                    .padding(.top, 7)
            }
            .foregroundStyle(palette.main)
            .frame(width: 165, height: 130, alignment: .topLeading)
            .offset(x: 10, y: 6)

            VStack(spacing: 10) {
                if showLastMonth { miniCalendar(month.adding(-1), height: 105) }
                if showNextMonth { miniCalendar(month.adding(1), height: 105) }
            }
            .frame(width: 165, height: 220, alignment: .top)
            .offset(x: 10, y: 140)

            photo(width: 370, height: 335)
                .offset(x: 201, y: 14)
        }
    }

    private func photo(width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                palette.pale
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private var calendarGrid: some View {
        let slots = daySlots()
        let rows = slots.count / 7
        let gap: CGFloat = template == .modern ? 0.5 : 1.5
        return VStack(spacing: gap) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { column in
                        let slot = slots[row * 7 + column]
                        VStack(spacing: 0) {
                            Text(String(slot.day))
                                .font(typography.day(19))
                                .foregroundStyle(dayColor(slot, column: column))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .padding(.top, 12)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(template == .gallery ? palette.pale : .white)
                        .overlay {
                            if template == .modern {
                                Rectangle().stroke(palette.border.opacity(0.4), lineWidth: 0.5)
                            }
                        }
                        .accessibilityLabel("\(slot.month.title) \(slot.day)日\(slot.isCurrent ? "" : "（隣月）")")
                    }
                }
            }
        }
        .frame(height: 425)
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
        if !slot.isCurrent { return Color(white: 0.86) }
        let sunday = firstWeekday == 1 ? 0 : 6
        let saturday = firstWeekday == 1 ? 6 : 5
        if column == sunday || Holidays.shared.name(month: slot.month, day: slot.day) != nil { return .red }
        if column == saturday { return palette.saturday }
        return .black
    }

    private func miniCalendar(_ target: Month, height: CGFloat = 150) -> some View {
        let days = target.days(firstWeekday: firstWeekday)
        let rows = Int(ceil(Double(days.count) / 7))
        let compact = height < 150
        return VStack(alignment: .leading, spacing: compact ? 1 : 2) {
            Text("\(target.month)月")
                .font(typography.month(compact ? 9 : 11))
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
                            .foregroundStyle(weekdayColor(column: column))
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(height: compact ? 10 : 14)
            }
            Spacer(minLength: 0)
        }
        .font(typography.day(compact ? 6.5 : 7.5))
        .padding(compact ? 6 : 8)
        .frame(width: 165, height: height)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(palette.border.opacity(0.4), lineWidth: 0.5))
    }

    private func weekdayColor(column: Int) -> Color {
        if column == (firstWeekday == 1 ? 0 : 6) { return .red }
        if column == (firstWeekday == 1 ? 6 : 5) { return palette.saturday }
        return .black
    }
}

private struct EditorView: View {
    @ObservedObject var model: EditorModel
    @State private var choosingImage = false
    @State private var showingImageEditor = false
    @State private var editorSource: NSImage?
    @State private var editorSettings = CropSettings()
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
                    if model.image != nil {
                        Button("画像を編集…") {
                            editorSource = model.originalImage ?? model.image
                            editorSettings = model.cropSettings
                            showingImageEditor = true
                        }
                        Button("画像を削除") {
                            model.image = nil
                            model.originalImage = nil
                            model.cropSettings = CropSettings()
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
                editorSource = image
                editorSettings = CropSettings()
                DispatchQueue.main.async { showingImageEditor = true }
            } catch {
                imageError = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingImageEditor) {
            if let source = editorSource {
                ImageCropEditor(source: source, initial: editorSettings) { cropped, settings in
                    model.originalImage = source
                    model.cropSettings = settings
                    model.image = cropped
                }
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
