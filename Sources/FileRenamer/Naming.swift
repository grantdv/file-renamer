import Foundation

// MARK: - Classification, naming rules, prompts

enum Naming {
    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "tiff", "bmp"]
    static let textExts: Set<String> = [
        "txt", "md", "markdown", "csv", "json", "log", "ini", "toml", "yaml", "yml", "xml",
        "swift", "py", "js", "ts", "html", "css", "sh", "rb", "go", "rs", "c", "h", "cpp"
    ]

    static func kind(of ext: String) -> FileKind {
        let e = ext.lowercased()
        if imageExts.contains(e) { return .image }
        if textExts.contains(e) { return .text }
        return .unsupported
    }

    /// Reduce a model's reply to a safe filename stem.
    static func sanitize(_ raw: String) -> String {
        var s = raw.lowercased()
        s = s.replacingOccurrences(of: "^[^a-z0-9]+|[^a-z0-9]+$", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        if s.count > 40 {
            s = String(s.prefix(40)).replacingOccurrences(of: "-+$", with: "", options: .regularExpression)
        }
        return s
    }

    /// File creation date as yyyy-MM-dd, for date-prefixed image names.
    static func datePrefix(for url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let d = (attrs?[.creationDate] as? Date) ?? (attrs?[.modificationDate] as? Date) ?? Date()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }

    static let imagePrompt = """
    You are a file-organizing assistant. Look at the photo and reply with ONLY a filename stem: \
    3 to 6 lowercase words joined by hyphens describing the main subject (example: golden-retriever-in-snow). \
    No quotes, no extension, no punctuation other than hyphens. If it is a screenshot, describe the content, not the app.
    """

    static func textPrompt(_ content: String) -> String {
        """
        You are a file-organizing assistant. Based on the file content below, reply with ONLY a filename stem: \
        3 to 6 lowercase words joined by hyphens describing the subject (example: quarterly-revenue-report). \
        No quotes, no extension, no punctuation other than hyphens.
        CONTENT:
        \(content)
        """
    }
}
