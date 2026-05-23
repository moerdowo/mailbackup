import SwiftUI

struct FilterPopover: View {
    @Bindable var model: MainModel

    private var useDateRange: Binding<Bool> {
        Binding(
            get: { model.filter.dateFrom != nil || model.filter.dateTo != nil },
            set: { on in
                if on {
                    if model.filter.dateFrom == nil {
                        model.filter.dateFrom = Calendar.current.date(byAdding: .month, value: -1, to: Date())
                    }
                    if model.filter.dateTo == nil { model.filter.dateTo = Date() }
                } else {
                    model.filter.dateFrom = nil
                    model.filter.dateTo = nil
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Sort", selection: $model.filter.sort) {
                Text(MessageSort.newest.label).tag(MessageSort.newest)
                Text(MessageSort.oldest.label).tag(MessageSort.oldest)
                if model.isSearchMode {
                    Text(MessageSort.relevance.label).tag(MessageSort.relevance)
                }
            }
            .pickerStyle(.menu)

            Divider()

            Toggle("Unread only", isOn: $model.filter.unreadOnly)
            Toggle("With attachments", isOn: $model.filter.hasAttachmentOnly)
            if !model.isSearchMode {
                Toggle("Group by conversation", isOn: $model.threaded)
            }

            Divider()

            Toggle("Date range", isOn: useDateRange)
            if useDateRange.wrappedValue {
                DatePicker("From", selection: Binding(
                    get: { model.filter.dateFrom ?? Date() },
                    set: { model.filter.dateFrom = $0 }
                ), displayedComponents: .date)
                DatePicker("To", selection: Binding(
                    get: { model.filter.dateTo ?? Date() },
                    set: { model.filter.dateTo = $0 }
                ), displayedComponents: .date)
            }
        }
        .padding(14)
        .frame(width: 290)
    }
}
