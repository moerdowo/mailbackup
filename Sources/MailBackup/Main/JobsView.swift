import SwiftUI

struct JobsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sync Jobs").font(.title2.bold())
                Spacer()
                if app.isSyncing {
                    Button(role: .destructive) { app.cancelSync() } label: {
                        Label("Stop", systemImage: "stop.circle")
                    }
                }
                Button("Clear Finished") { app.clearFinishedJobs() }
                    .disabled(app.jobs.allSatisfy { $0.status == .running || $0.status == .queued })
            }
            .padding()
            Divider()

            if app.jobs.isEmpty {
                ContentUnavailableView("No sync jobs yet", systemImage: "arrow.triangle.2.circlepath",
                                       description: Text("Trigger a sync from the dashboard or an account."))
            } else {
                List(app.jobs) { job in
                    JobRow(job: job)
                }
            }
        }
    }
}

private struct JobRow: View {
    let job: SyncJobRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.accountEmail).font(.headline)
                Spacer()
                statusBadge
            }
            Text("\(job.folderNames.count) folder\(job.folderNames.count == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)

            if job.status == .running, let progress = job.progress {
                if progress.messagesTotal > 0 {
                    ProgressView(value: Double(progress.messagesDone), total: Double(progress.messagesTotal)) {
                        Text("\(progress.phase) \(progress.folderName)").font(.caption)
                    } currentValueLabel: {
                        Text("\(progress.messagesDone) of \(progress.messagesTotal)").font(.caption)
                    }
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(progress.phase).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                if job.status == .completed {
                    Label("\(job.messagesArchived) new", systemImage: "tray.and.arrow.down")
                }
                if let started = job.startedAt {
                    Label(started.formatted(date: .abbreviated, time: .shortened), systemImage: "play")
                }
                if let finished = job.finishedAt {
                    Label(finished.formatted(date: .omitted, time: .shortened), systemImage: "flag.checkered")
                }
            }
            .font(.caption2).foregroundStyle(.secondary)

            if let error = job.error {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        Text(job.status.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(badgeColor.opacity(0.18), in: Capsule())
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        switch job.status {
        case .queued: return .secondary
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
}
