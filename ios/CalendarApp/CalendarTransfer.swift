import Foundation
import SwiftUI
import UniformTypeIdentifiers

private struct CalendarArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CalendarTransferError.invalidBackup }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct CalendarTransferSheet: View {
    @EnvironmentObject private var store: CalendarStore
    @State private var importing = false
    @State private var exporting = false
    @State private var document: CalendarArchiveDocument?
    @State private var pending: PendingImport?
    @State private var message: String?
    let kind: Kind

    enum Kind: Equatable {
        case backup, calendar
        var title: String { self == .backup ? "备份与恢复" : "导入日历文件" }
        var contentType: UTType { self == .backup ? .json : (UTType(filenameExtension: "ics") ?? .data) }
    }

    private struct PendingImport {
        let items: [CalendarItem]
        let skipped: Int
    }

    var body: some View {
        Form {
            Section {
                if kind == .backup {
                    Button(action: makeBackup) { Label("备份到文件", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("calendar-export-backup")
                }
                Button { importing = true } label: {
                    Label(kind == .backup ? "从备份恢复" : "选择 .ics 文件", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("calendar-import-file")
            } footer: {
                Text(kind == .backup
                     ? "备份包含自建日程、生日、纪念日、倒数日和提醒设置。恢复时合并新记录。"
                     : "从「文件」选择日历导出文件。重复导入会跳过已存在的日程。复杂重复规则或无法换算时区的条目会在导入前提示。")
            }
            if let message { Section { Text(message).foregroundStyle(.secondary) } }
        }
        .scrollContentBackground(.hidden)
        .background { CalendarTheme.background }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: "日历备份-\(CivilDay.today.key)") { result in
            switch result {
            case .success: message = "备份已保存。"
            case .failure(let error): message = error.localizedDescription
            }
            document = nil
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [kind.contentType], onCompletion: prepareImport)
        .confirmationDialog(kind == .backup ? "恢复备份" : "导入日历", isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }
        ), titleVisibility: .visible, presenting: pending) { prepared in
            Button(kind == .backup ? "合并备份" : "导入日程") { finishImport(prepared) }
            Button("取消", role: .cancel) { pending = nil }
        } message: { prepared in
            Text("读取到 \(prepared.items.count) 条记录。" + (prepared.skipped == 0 ? "" : " 有 \(prepared.skipped) 条无法导入。"))
        }
    }

    private func makeBackup() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            document = CalendarArchiveDocument(data: try encoder.encode(CalendarArchive(items: store.items)))
            exporting = true
        } catch {
            message = error.localizedDescription
        }
    }

    private func prepareImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 16 * 1024 * 1024 {
                throw CalendarTransferError.fileTooLarge
            }
            let data = try Data(contentsOf: url)
            guard data.count <= 16 * 1024 * 1024 else { throw CalendarTransferError.fileTooLarge }
            let prepared: PendingImport
            if kind == .backup {
                prepared = PendingImport(items: try CalendarArchive.read(data), skipped: 0)
            } else {
                let parsed = try CalendarICS.read(data, displayTimeZone: store.timeZone)
                prepared = PendingImport(items: parsed.items, skipped: parsed.skipped)
            }
            if prepared.items.isEmpty {
                message = prepared.skipped == 0 ? "文件中没有记录。" : "文件中的 \(prepared.skipped) 条记录都无法导入。"
            } else {
                pending = prepared
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func finishImport(_ prepared: PendingImport) {
        let imported = store.mergePersonalItems(prepared.items)
        let duplicates = prepared.items.count - imported
        message = "已添加 \(imported) 条，跳过 \(duplicates) 条重复记录。" +
            (prepared.skipped == 0 ? "" : " 另有 \(prepared.skipped) 条无法导入。")
        pending = nil
        if imported > 0, prepared.items.contains(where: { $0.reminder != nil }) {
            Task { await CalendarNotifications.shared.requestPermission(for: store) }
        }
    }
}
