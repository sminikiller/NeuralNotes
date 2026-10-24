import SwiftUI
import NeuralNotesCore

@MainActor
struct NotebookCloudBadge: View {
    let documentID: UUID
    @Bindable private var cloud = CloudBackupService.shared
    @Bindable private var iCloud = CloudNotebookSync.shared
    private var state: (title: String, icon: String, conflict: Bool) {
        if cloud.conflicts[documentID] != nil || iCloud.conflicts[documentID] != nil || cloud.queue.jobs.contains(where: { $0.documentID == documentID && $0.conflict }) {
            return ("Conflitto · versioni conservate", "exclamationmark.icloud", true)
        }
        if cloud.queue.jobs.contains(where: { $0.documentID == documentID }) { return ("In coda", "arrow.clockwise.icloud", false) }
        if let document = cloud.documents.first(where: { $0.id == documentID }) {
            let date = document.updatedAt.map { " · " + $0.formatted(date: .numeric, time: .omitted) } ?? ""
            return ("Nel cloud" + date, "checkmark.icloud", false)
        }
        return ("Solo sull’iPad", "internaldrive", false)
    }
    var body: some View {
        Label(state.title, systemImage: state.icon).font(.caption2).lineLimit(1)
            .foregroundStyle(state.conflict ? Color.orange : Color.primary)
            .padding(.horizontal, 8).padding(.vertical, 5).background(.regularMaterial, in: Capsule())
            .accessibilityLabel(state.title)
    }
}
