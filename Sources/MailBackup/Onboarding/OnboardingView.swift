import SwiftUI
import AppKit

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @State private var model: OnboardingModel?
    let onFinish: () -> Void

    var body: some View {
        Group {
            if let model {
                OnboardingContent(model: model, onFinish: onFinish)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if model == nil { model = OnboardingModel(app: app) }
        }
    }
}

private struct OnboardingContent: View {
    @Bindable var model: OnboardingModel
    @Environment(AppModel.self) private var app
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                StepIndicator(current: model.step)
                if app.hasAccounts {
                    HStack {
                        Button {
                            onFinish()
                        } label: {
                            Label("Cancel", systemImage: "chevron.left")
                        }
                        .buttonStyle(.borderless)
                        .keyboardShortcut(.cancelAction)
                        .help("Back to dashboard")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 20)
            Divider()
            ScrollView {
                stepView
                    .padding(28)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 640, minHeight: 560)
    }

    @ViewBuilder
    private var stepView: some View {
        switch model.step {
        case .welcome: WelcomeStep(model: model)
        case .account: AccountStep(model: model)
        case .folders: FoldersStep(model: model)
        case .options: OptionsStep(model: model)
        case .sync: SyncStep(model: model, onFinish: onFinish)
        }
    }
}

private struct StepIndicator: View {
    let current: OnboardingModel.Step
    private let titles: [(OnboardingModel.Step, String)] = [
        (.welcome, "Welcome"), (.account, "Account"), (.folders, "Folders"),
        (.options, "Options"), (.sync, "Archive"),
    ]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(titles, id: \.0) { step, title in
                HStack(spacing: 6) {
                    Circle()
                        .fill(step.rawValue <= current.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 9, height: 9)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(step == current ? .primary : .secondary)
                }
            }
        }
    }
}

// MARK: - Welcome

private struct WelcomeStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Welcome to MailBackup")
                .font(.largeTitle.bold())
            Text("Archive and back up your email locally over IMAP. Your messages are stored on this Mac as standard .eml files — nothing is sent anywhere else.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Get Started") { model.step = .account }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .padding(.top, 8)
        }
    }
}

// MARK: - Account

private struct AccountStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add your IMAP account")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("Quick setup").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(MailProvider.presets) { provider in
                        Button(provider.name) { model.applyPreset(provider) }
                            .buttonStyle(.bordered)
                    }
                }
                if let note = model.providerNote {
                    Label(note, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Name").gridColumnAlignment(.trailing)
                    TextField("Your name (optional)", text: $model.displayName)
                }
                GridRow {
                    Text("Email")
                    TextField("you@example.com", text: $model.email)
                        .onChange(of: model.email) { _, new in
                            if model.username.isEmpty { /* username defaults to email */ }
                            _ = new
                        }
                }
                GridRow {
                    Text("Password")
                    SecureField("Password or app password", text: $model.password)
                }
                GridRow {
                    Text("IMAP host")
                    TextField("imap.example.com", text: $model.host)
                }
                GridRow {
                    Text("Port")
                    HStack {
                        TextField("993", text: $model.port).frame(width: 80)
                        Picker("Security", selection: $model.security) {
                            ForEach(ConnectionSecurity.allCases, id: \.self) { security in
                                Text(security.displayName).tag(security)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                }
                GridRow {
                    Text("Username")
                    TextField("Defaults to email", text: $model.username)
                }
            }
            .textFieldStyle(.roundedBorder)

            if let error = model.foldersError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Button("Back") { model.step = .welcome }
                Spacer()
                if model.isLoadingFolders { ProgressView().controlSize(.small) }
                Button("Connect") {
                    Task { await model.connectAndLoadFolders() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canContinueFromAccount || model.isLoadingFolders)
            }
        }
    }
}

// MARK: - Folders

private struct FoldersStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose folders to archive")
                .font(.title2.bold())
            Text("\(model.selectedFolders.count) of \(model.mailboxes.count) selected")
                .font(.callout).foregroundStyle(.secondary)

            HStack {
                Button("Select All") { model.selectedFolders = Set(model.mailboxes.map(\.name)) }
                Button("Select None") { model.selectedFolders = [] }
            }
            .controlSize(.small)

            List {
                ForEach(model.mailboxes) { mailbox in
                    Toggle(isOn: Binding(
                        get: { model.selectedFolders.contains(mailbox.name) },
                        set: { isOn in
                            if isOn { model.selectedFolders.insert(mailbox.name) }
                            else { model.selectedFolders.remove(mailbox.name) }
                        }
                    )) {
                        Label(mailbox.name, systemImage: "folder")
                    }
                }
            }
            .frame(height: 280)
            .border(Color.secondary.opacity(0.2))

            HStack {
                Button("Back") { model.step = .account }
                Spacer()
                Button("Continue") { model.step = .options }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selectedFolders.isEmpty)
            }
        }
    }
}

// MARK: - Options

private struct OptionsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Archive options")
                .font(.title2.bold())

            Toggle("Download attachments", isOn: $model.downloadAttachments)

            Picker("Sync automatically", selection: $model.syncInterval) {
                ForEach(SyncInterval.allCases) { interval in
                    Text(interval.displayName).tag(interval)
                }
            }
            .frame(maxWidth: 320)

            VStack(alignment: .leading, spacing: 6) {
                Text("Archive location").font(.headline)
                HStack {
                    Text(model.customArchivePath ?? app.archiveRoot.path)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { chooseFolder() }
                }
                Text("Messages are stored as .eml files in this folder.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let error = model.setupError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.callout)
            }

            HStack {
                Button("Back") { model.step = .folders }
                Spacer()
                Button("Start Archiving") { model.startInitialSync() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    @Environment(AppModel.self) private var app

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            model.customArchivePath = url.path
        }
    }
}

// MARK: - Sync

private struct SyncStep: View {
    @Bindable var model: OnboardingModel
    @Environment(AppModel.self) private var app
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            if let error = app.syncError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48)).foregroundStyle(.red)
                Text("Sync stopped").font(.title2.bold())
                Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack {
                    Button("Continue Anyway") { onFinish() }
                    Button("Retry") { model.retryInitialSync() }
                        .keyboardShortcut(.defaultAction)
                }
            } else if !app.isSyncing {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56)).foregroundStyle(.green)
                Text("Archive complete").font(.title2.bold())
                Button("Open MailBackup") { onFinish() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            } else {
                ProgressView().controlSize(.large)
                Text(app.syncProgress?.phase ?? "Starting…").font(.headline)
                if let progress = app.syncProgress, progress.messagesTotal > 0 {
                    ProgressView(value: Double(progress.messagesDone), total: Double(progress.messagesTotal)) {
                        Text(progress.folderName)
                    } currentValueLabel: {
                        Text("\(progress.messagesDone) of \(progress.messagesTotal)")
                    }
                    .frame(maxWidth: 360)
                }
                if let progress = app.syncProgress, progress.folderCount > 0 {
                    Text("Folder \(progress.folderIndex) of \(progress.folderCount)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("You can keep using MailBackup while this runs.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Continue in Background") { onFinish() }
                    .controlSize(.large)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}
