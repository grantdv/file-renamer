import Foundation

// MARK: - Provider (any OpenAI-compatible chat endpoint)

public struct Provider: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name: String
    public var baseURL: String
    public var apiKey: String
    public var model: String
    public var supportsVision: Bool

    public init(id: UUID = UUID(), name: String, baseURL: String, apiKey: String, model: String, supportsVision: Bool) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.supportsVision = supportsVision
    }
}

public struct FolderConfig: Codable, Equatable, Identifiable {
    public var path: String
    public var autoApprove: Bool
    /// When this folder was added. Files that existed before this moment
    /// are only named via the explicit “Rename all files in folder…” action.
    public var activatedAt: Date
    public var id: String { path }

    public init(path: String, autoApprove: Bool, activatedAt: Date = Date()) {
        self.path = path
        self.autoApprove = autoApprove
        self.activatedAt = activatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        autoApprove = try c.decodeIfPresent(Bool.self, forKey: .autoApprove) ?? false
        // Old configs predate this field: treat the upgrade moment as activation.
        activatedAt = try c.decodeIfPresent(Date.self, forKey: .activatedAt) ?? Date()
    }
}

// MARK: - Naming style

public enum DatePrefixMode: String, Codable {
    case off, images, all

    public init(rawValue: String) { self = DatePrefixMode(rawValue: rawValue) ?? .images }
    public static let allCases: [DatePrefixMode] = [.off, .images, .all]

    public var display: String {
        switch self {
        case .off: return "Off"
        case .images: return "Images only"
        case .all: return "All files"
        }
    }
}

public enum CaseStyle: String, Codable {
    case kebab, camel, title

    public init(rawValue: String) { self = CaseStyle(rawValue: rawValue) ?? .kebab }
    public static let allCases: [CaseStyle] = [.kebab, .camel, .title]

    public var display: String {
        switch self {
        case .kebab: return "Kebab-case"
        case .camel: return "camelCase"
        case .title: return "Title Case"
        }
    }
}

public enum WordCountStyle: String, Codable {
    case short, medium, long

    public init(rawValue: String) { self = WordCountStyle(rawValue: rawValue) ?? .medium }
    public static let allCases: [WordCountStyle] = [.short, .medium, .long]

    public var range: String {
        switch self {
        case .short: return "2 to 4"
        case .medium: return "3 to 6"
        case .long: return "4 to 8"
        }
    }

    public var display: String { "\(range) words" }
}

public struct NamingStyle: Codable, Equatable {
    public var datePrefix: DatePrefixMode = .images
    public var dateFormat: String = "yyyy-MM-dd"
    public var wordCount: WordCountStyle = .medium
    public var caseStyle: CaseStyle = .kebab
    public var customRules: String = ""

    public init() {}
}

public struct AppSettings: Codable {
    public var providers: [Provider] = []
    public var imageProviderID: UUID?
    public var textProviderID: UUID?
    public var folders: [FolderConfig] = []
    public var paused: Bool = false
    public var naming: NamingStyle = NamingStyle()

    public init() {}

    public func provider(id: UUID?) -> Provider? {
        guard let id else { return nil }
        return providers.first { $0.id == id }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        providers = try c.decodeIfPresent([Provider].self, forKey: .providers) ?? []
        imageProviderID = try c.decodeIfPresent(UUID.self, forKey: .imageProviderID)
        textProviderID = try c.decodeIfPresent(UUID.self, forKey: .textProviderID)
        folders = try c.decodeIfPresent([FolderConfig].self, forKey: .folders) ?? []
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        naming = try c.decodeIfPresent(NamingStyle.self, forKey: .naming) ?? NamingStyle()
    }
}

// MARK: - Pipeline types

public struct Suggestion: Identifiable, Equatable {
    public let id = UUID()
    public let url: URL
    public let proposedName: String
    public let source: String
    public let autoApprove: Bool
    public let batchID: UUID

    public init(url: URL, proposedName: String, source: String, autoApprove: Bool, batchID: UUID) {
        self.url = url
        self.proposedName = proposedName
        self.source = source
        self.autoApprove = autoApprove
        self.batchID = batchID
    }

    public var oldName: String { url.lastPathComponent }
    public var newURL: URL { url.deletingLastPathComponent().appendingPathComponent(proposedName) }
}

public struct ActivityEvent: Codable, Identifiable {
    public var id = UUID()
    public var date: Date
    public var kind: String   // queued, renamed, approved, skipped, error
    public var message: String

    public init(date: Date, kind: String, message: String) {
        self.date = date
        self.kind = kind
        self.message = message
    }

    public var line: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return "\(f.string(from: date))  \(kind.padding(toLength: 8, withPad: " ", startingAt: 0))  \(message)"
    }
}

public struct RenameRecord: Codable, Identifiable {
    public var id = UUID()
    public var oldPath: String
    public var newPath: String
    public var batchID: UUID
    public var date: Date

    public init(oldPath: String, newPath: String, batchID: UUID, date: Date) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.batchID = batchID
        self.date = date
    }
}

public enum FileKind { case image, text, unsupported }

extension URL {
    public var isRegularFile: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
    }
}
