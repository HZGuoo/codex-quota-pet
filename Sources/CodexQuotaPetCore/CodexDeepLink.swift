import Foundation

public enum CodexDeepLink {
    /// Builds the desktop-app route used to open a local Codex conversation.
    /// The thread identifier is treated as one opaque path component.
    public static func conversationURL(threadID: String) -> URL? {
        let identifier = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty, identifier.count <= 512 else { return nil }

        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/%?#")
        guard let encodedIdentifier = identifier.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.percentEncodedPath = "/\(encodedIdentifier)"
        return components.url
    }
}
