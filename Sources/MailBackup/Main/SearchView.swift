import SwiftUI

struct SearchView: View {
    @Bindable var model: MainModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                searchField
                Divider()
                results
            }
            .frame(minWidth: 300, idealWidth: 360)

            MessageDetailView(model: model)
                .frame(minWidth: 420)
        }
        .onAppear { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search all archived mail", text: $model.searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onChange(of: model.searchText) { _, _ in model.refreshMessages() }
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                    model.refreshMessages()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private var results: some View {
        if model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView("Search your archive", systemImage: "magnifyingglass")
        } else if model.messages.isEmpty {
            ContentUnavailableView("No matches", systemImage: "magnifyingglass")
        } else {
            List(model.messages, selection: $model.selectedMessageId) { message in
                VStack(alignment: .leading, spacing: 2) {
                    MessageRow(message: message)
                    Text(model.contextLabel(for: message))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .tag(message.id)
            }
        }
    }
}
