import SwiftUI

struct AccountSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let account: Account

    @State private var displayName: String
    @State private var host: String
    @State private var port: String
    @State private var security: ConnectionSecurity
    @State private var username: String
    @State private var newPassword = ""
    @State private var syncInterval: SyncInterval
    @State private var isPaused: Bool

    @State private var archivedFolders: [String] = []
    @State private var folderOptions: [String] = []
    @State private var selectedFolders: Set<String> = []
    @State private var loadingFolders = false
    @State private var foldersError: String?

    init(account: Account) {
        self.account = account
        _displayName = State(initialValue: account.displayName)
        _host = State(initialValue: account.imapHost)
        _port = State(initialValue: String(account.imapPort))
        _security = State(initialValue: account.security)
        _username = State(initialValue: account.username)
        _syncInterval = State(initialValue: SyncInterval(minutes: account.syncIntervalMinutes))
        _isPaused = State(initialValue: account.isPaused)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Account Settings").font(.title2.bold())
                Spacer()
            }
            .padding()
            Divider()

            Form {
                Section("Connection") {
                    TextField("Display name", text: $displayName)
                    LabeledContent("Email", value: account.email)
                    TextField("IMAP host", text: $host)
                    TextField("Port", text: $port)
                    Picker("Security", selection: $security) {
                        ForEach(ConnectionSecurity.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    TextField("Username", text: $username)
                    SecureField("New password (leave blank to keep current)", text: $newPassword)
                }

                Section("Sync") {
                    Picker("Sync automatically", selection: $syncInterval) {
                        ForEach(SyncInterval.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Pause syncing this account", isOn: $isPaused)
                }

                Section {
                    if folderOptions.isEmpty {
                        Text("No folders.").foregroundStyle(.secondary)
                    } else {
                        ForEach(folderOptions, id: \.self) { name in
                            Toggle(isOn: Binding(
                                get: { selectedFolders.contains(name) },
                                set: { on in
                                    if on { selectedFolders.insert(name) } else { selectedFolders.remove(name) }
                                }
                            )) {
                                Label(name, systemImage: "folder")
                            }
                        }
                    }
                    Button {
                        loadServerFolders()
                    } label: {
                        if loadingFolders {
                            HStack { ProgressView().controlSize(.small); Text("Loading…") }
                        } else {
                            Label("Refresh folder list from server", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(loadingFolders)
                    if let foldersError {
                        Text(foldersError).font(.caption).foregroundStyle(.red)
                    }
                    Text("Unchecking a folder deletes its local archive.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text("Folders to archive")
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 540, height: 640)
        .onAppear(perform: loadCurrentFolders)
    }

    private func loadCurrentFolders() {
        let folders = ((try? app.repository.folders(accountId: account.id)) ?? []).map(\.name)
        archivedFolders = folders
        folderOptions = folders.sorted { $0.lowercased() < $1.lowercased() }
        selectedFolders = Set(folders)
    }

    private func loadServerFolders() {
        loadingFolders = true
        foldersError = nil
        let password = newPassword.isEmpty ? (app.password(for: account) ?? "") : newPassword
        var probe = account
        probe.imapHost = host
        probe.imapPort = Int(port) ?? account.imapPort
        probe.security = security
        probe.username = username.isEmpty ? account.username : username

        Task {
            do {
                let entries = try await app.syncEngine.listFolders(account: probe, password: password)
                await MainActor.run {
                    let names = Set(entries.filter(\.selectable).map(\.name)).union(archivedFolders)
                    folderOptions = names.sorted { $0.lowercased() < $1.lowercased() }
                    loadingFolders = false
                }
            } catch {
                await MainActor.run {
                    foldersError = error.localizedDescription
                    loadingFolders = false
                }
            }
        }
    }

    private func save() {
        var updated = account
        updated.displayName = displayName.isEmpty ? account.email : displayName
        updated.imapHost = host
        updated.imapPort = Int(port) ?? account.imapPort
        updated.security = security
        updated.username = username.isEmpty ? account.email : username
        updated.syncIntervalMinutes = syncInterval.minutes
        updated.isPaused = isPaused

        app.updateAccount(updated, newPassword: newPassword.isEmpty ? nil : newPassword)
        if selectedFolders != Set(archivedFolders) {
            app.applyFolderSelection(account: updated, selectedNames: selectedFolders)
        }
        dismiss()
    }
}
