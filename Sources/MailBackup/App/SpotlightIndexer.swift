import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Indexes archived messages into CoreSpotlight so macOS system search finds
/// them. Items are keyed by message row id and grouped by account id (domain).
enum SpotlightIndexer {
    private static func identifier(for id: Int64) -> String { "mailbackup.message.\(id)" }

    static func index(_ message: Message) {
        guard let id = message.id else { return }
        CSSearchableIndex.default().indexSearchableItems([item(for: message, id: id)])
    }

    static func index(_ messages: [Message]) {
        let items = messages.compactMap { message -> CSSearchableItem? in
            guard let id = message.id else { return nil }
            return item(for: message, id: id)
        }
        guard !items.isEmpty else { return }
        CSSearchableIndex.default().indexSearchableItems(items)
    }

    static func deindexAccount(_ accountId: String) {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [accountId])
    }

    static func deindexMessages(ids: [Int64]) {
        guard !ids.isEmpty else { return }
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids.map(identifier(for:)))
    }

    private static func item(for message: Message, id: Int64) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .emailMessage)
        attributes.title = message.subject
        attributes.contentDescription = message.snippet ?? message.fromAddress
        attributes.contentCreationDate = message.internalDate ?? message.date
        if let address = message.fromAddress { attributes.emailAddresses = [address] }
        if let name = message.fromName { attributes.authorNames = [name] }
        return CSSearchableItem(
            uniqueIdentifier: identifier(for: id),
            domainIdentifier: message.accountId,
            attributeSet: attributes
        )
    }
}
