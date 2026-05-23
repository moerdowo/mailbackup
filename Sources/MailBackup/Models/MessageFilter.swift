import Foundation

enum MessageSort: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case relevance  // search only

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest: return "Newest first"
        case .oldest: return "Oldest first"
        case .relevance: return "Best match"
        }
    }
}

/// Filters/sort applied to the folder and search message lists.
struct MessageFilter: Equatable {
    var unreadOnly = false
    var hasAttachmentOnly = false
    var sort: MessageSort = .newest

    var isActive: Bool { unreadOnly || hasAttachmentOnly }
}
