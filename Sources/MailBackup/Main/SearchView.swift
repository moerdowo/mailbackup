import SwiftUI

struct SearchView: View {
    @Bindable var model: MainModel
    @FocusState private var searchFocused: Bool

    private var hasQuery: Bool {
        !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            HSplitView {
                results
                    .frame(minWidth: 300, idealWidth: 380, maxHeight: .infinity)
                MessageDetailView(model: model)
                    .frame(minWidth: 420, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
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
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            if hasQuery {
                Text("\(model.searchTotal) result\(model.searchTotal == 1 ? "" : "s")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var results: some View {
        if !hasQuery {
            ContentUnavailableView("Search your archive",
                                   systemImage: "magnifyingglass",
                                   description: Text("Find mail across all of your accounts."))
        } else if model.messages.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else {
            List(selection: $model.selectedMessageId) {
                ForEach(model.messages) { message in
                    VStack(alignment: .leading, spacing: 3) {
                        MessageRow(message: message)
                        Text(model.contextLabel(for: message))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(message.id)
                }
                if model.hasMoreMessages {
                    PagingFooter().onAppear { model.loadMore() }
                }
            }
        }
    }
}
