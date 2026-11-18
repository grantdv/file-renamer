import Foundation

// MARK: - Provider (any OpenAI-compatible chat endpoint)

struct Provider: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var baseURL: String
    var apiKey: String
    var model: String
    var supportsVision: Bool
}

struct FolderConfig: Codable, Equatable, Identifiable {
    var path: String
    var autoApprove: Bool
    var id: String { path }
}

struct AppSettings: Codable {
    var providers: [Provider] = []
    var imageProviderID: UUID?
    var textProviderID: UUID?
    var folders: [FolderConfig] = []
    var paused: Bool = false

    func provider(id: UUID?) -> Provider? {
        guard let id else { return nil }
        return providers.first { $0.id == id }
    }
}

// MARK: - Pipeline types

struct Suggestion: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let proposedName: String
    let source: String
    let autoApprove: Bool
    let batchID: UUID

    var oldName: String { url.lastPathComponent }
    var newURL: URL { url.deletingLastPathComponent().appendingPathComponent(proposedName) }
}

struct RenameRecord: Codable, Identifiable {
    var id = UUID()
    var oldPath: String
    var newPath: String
    var batchID: UUID
    var date: Date
}

enum FileKind { case image, text, unsupported }

extension URL {
    var isRegularFile: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
    }
}
