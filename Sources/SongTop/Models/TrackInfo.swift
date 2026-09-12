import Foundation

public struct TrackInfo: Equatable, Identifiable {
    public var id: String { url }
    public let rawTitle: String
    public let title: String
    public let artist: String
    public let url: String
    public let browser: String
    public let isPlaying: Bool
    
    public init(rawTitle: String, url: String, browser: String, isPlaying: Bool = true) {
        self.rawTitle = rawTitle
        self.url = url
        self.browser = browser
        self.isPlaying = isPlaying
        
        let cleaned = TrackInfo.cleanRawTitle(rawTitle)
        let parsed = TrackInfo.parseArtistAndTitle(cleaned)
        self.title = parsed.title
        self.artist = parsed.artist
    }
    
    public var displayTitle: String {
        if !artist.isEmpty && artist != title {
            return "\(title) • \(artist)"
        }
        return title
    }
    
    public static func cleanRawTitle(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove leading notifications like (1) or (99+)
        if let regex = try? NSRegularExpression(pattern: #"^\(\d+\+?\)\s*"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: text.utf16.count), withTemplate: "")
        }
        
        // Remove play symbols ▶, ▷, etc.
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "▶▷► \t"))
        
        // Remove common YouTube suffixes
        let suffixes = [
            " - YouTube Music",
            " - YouTube",
            " | YouTube Music",
            " | YouTube"
        ]
        for suffix in suffixes {
            if text.hasSuffix(suffix) {
                text = String(text.dropLast(suffix.count))
            }
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public static func parseArtistAndTitle(_ text: String) -> (title: String, artist: String) {
        // Check for YouTube Music format: "Song Title • Artist"
        if text.contains(" • ") {
            let parts = text.components(separatedBy: " • ")
            if parts.count >= 2 {
                return (title: parts[0].trimmingCharacters(in: .whitespaces),
                        artist: parts[1].trimmingCharacters(in: .whitespaces))
            }
        }
        
        // Check for "Artist - Title" or "Title - Artist"
        if text.contains(" - ") {
            let parts = text.components(separatedBy: " - ")
            if parts.count == 2 {
                let first = parts[0].trimmingCharacters(in: .whitespaces)
                let second = parts[1].trimmingCharacters(in: .whitespaces)
                
                // Usually on YouTube music videos it's "Artist - Song Name"
                return (title: second, artist: first)
            }
        }
        
        // Check for "Artist \"Song Title\"" or "Song Title | Channel"
        if text.contains(" | ") {
            let parts = text.components(separatedBy: " | ")
            if parts.count >= 2 {
                return (title: parts[0].trimmingCharacters(in: .whitespaces),
                        artist: parts[1].trimmingCharacters(in: .whitespaces))
            }
        }
        
        return (title: text, artist: "")
    }
}
