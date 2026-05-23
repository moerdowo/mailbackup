import Foundation

/// A named, persisted search query shown in the sidebar as a smart folder.
struct SavedSearch: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var query: String

    init(id: UUID = UUID(), name: String, query: String) {
        self.id = id
        self.name = name
        self.query = query
    }
}
