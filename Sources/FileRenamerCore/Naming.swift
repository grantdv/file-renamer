import Foundation
import PDFKit

// MARK: - Classification, naming rules, prompts

enum Naming {
    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "tiff", "bmp"]
    static let textExts: Set<String> = [
        "txt", "md", "markdown", "csv", "json", "log", "ini", "toml", "yaml", "yml", "xml",
        "swift", "py", "js", "ts", "html", "css", "sh", "rb", "go", "rs", "c", "h", "cpp",
        "pdf"
    ]

    // MARK: PDF text extraction

    /// Readable text from a PDF's first pages (capped), via PDFKit.
    /// Returns nil when the PDF can't be opened or has no text layer
    /// (scanned/image-only or protected documents).
    static func pdfText(_ url: URL, maxPages: Int = 5, maxChars: Int = 4000) -> String? {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { return nil }
        var pages: [String] = []
        for i in 0..<min(doc.pageCount, maxPages) {
            if let s = doc.page(at: i)?.string,
               !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pages.append(s)
            }
        }
        let text = pages.joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return String(text.prefix(maxChars))
    }

    /// The PDF's embedded Title metadata, if it carries one.
    /// Used as a naming fallback when no text provider is configured or it fails.
    static func pdfTitle(_ url: URL) -> String? {
        guard let doc = PDFDocument(url: url), let cg = doc.documentRef, let info = cg.info else { return nil }
        var titleRef: CGPDFStringRef?
        guard CGPDFDictionaryGetString(info, "Title", &titleRef) else { return nil }
        guard let raw = titleRef.flatMap({ CGPDFStringCopyTextString($0) as String? }) else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func kind(of ext: String) -> FileKind {
        let e = ext.lowercased()
        if imageExts.contains(e) { return .image }
        if textExts.contains(e) { return .text }
        return .unsupported
    }

    /// Reduce a model's reply to a clean name stem in the chosen case style.
    static func sanitize(_ raw: String, style: CaseStyle) -> String {
        let words = raw.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
        switch style {
        case .kebab:
            var s = words.joined(separator: "-")
            if s.count > 40 {
                s = String(s.prefix(40)).replacingOccurrences(of: "-+$", with: "", options: .regularExpression)
            }
            return s
        case .camel:
            guard let first = words.first else { return "" }
            var s = first
            for w in words.dropFirst() { s += w.prefix(1).uppercased() + w.dropFirst() }
            return String(s.prefix(40))
        case .title:
            let s = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
            return String(s.prefix(40))
        }
    }

    /// File creation date formatted with the user's date format, for date-prefixed names.
    static func datePrefix(for url: URL, format: String) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let d = (attrs?[.creationDate] as? Date) ?? (attrs?[.modificationDate] as? Date) ?? Date()
        let f = DateFormatter()
        f.dateFormat = format.isEmpty ? "yyyy-MM-dd" : format
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }

    static func imagePrompt(_ style: NamingStyle) -> String {
        var p = """
        You are a file-organizing assistant. Look at the photo and reply with ONLY a filename stem: \
        \(style.wordCount.range) lowercase words joined by hyphens describing the main subject (example: golden-retriever-in-snow). \
        No quotes, no extension, no punctuation other than hyphens. If it is a screenshot, describe the content, not the app.
        """
        if !style.customRules.trimmingCharacters(in: .whitespaces).isEmpty {
            p += "\nAdditional rules: \(style.customRules)"
        }
        return p
    }

    static func textPrompt(_ content: String, style: NamingStyle) -> String {
        var p = """
        You are a file-organizing assistant. Based on the file content below, reply with ONLY a filename stem: \
        \(style.wordCount.range) lowercase words joined by hyphens describing the subject (example: quarterly-revenue-report). \
        No quotes, no extension, no punctuation other than hyphens.
        CONTENT:
        \(content)
        """
        if !style.customRules.trimmingCharacters(in: .whitespaces).isEmpty {
            p += "\nAdditional rules: \(style.customRules)"
        }
        return p
    }

    /// Fast, free heuristic: does this filename look machine-generated (camera roll,
    /// OS default, duplicate marker, date-only) rather than a name a human chose?
    /// When true we may rename it; when false the file is treated as already named.
    static func looksAutoNamed(_ filename: String) -> Bool {
        let stem = (filename as NSString).deletingPathExtension.lowercased()
        guard !stem.isEmpty else { return true }
        let patterns = [
            #"^[\d._\- ]+$"#,   // all digits / separators
            #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#,  // uuid
            #"^\d{4}-\d{2}-\d{2}([-_ ]?(photo|image|screenshot|screen shot|scan|pic|picture|img|dsc)?\d*)?$"#,  // date-only or date + generic word
            #"^(img|dsc|dcim|pxl|ivm)([_- ]?\d+)*$"#,  // camera / phone sequences
            #"^(photo|picture|image|pic|screenshot|scan|download|untitled|copy|temp|temporary|sample|test|output|export|file|document|notes?|draft|new|report)([-_ ]?\d+)?$"#,  // single generic word
            #"^new (file|folder|document)( \d+)?$"#,
            #"^screenshot( |$)"#,  // "Screenshot 2026-11-18 at 07.31.00"
            #"^screen[-_ ]?shot"#,
            #"^copy of .+$"#,
            #" \(\d+\)$"#  // trailing " (2)" duplicate marker
        ]
        return patterns.contains { stem.range(of: $0, options: .regularExpression) != nil }
    }
}
