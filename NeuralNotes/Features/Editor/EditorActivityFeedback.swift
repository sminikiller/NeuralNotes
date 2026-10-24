import SwiftUI

/// Autosave is quiet. Explicit actions get a short, non-blocking confirmation.
@MainActor
struct EditorActivityFeedback: View {
    let message: String
    @State private var visible: String?
    @State private var notification = UUID()

    private static let quiet: Set<String> = [
        "Apertura…", "Salvato sul dispositivo", "Modifiche da salvare", "Salvataggio…"
    ]

    var body: some View {
        Group {
            if let visible {
                Text(visible).font(.subheadline).lineLimit(3)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.1)))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
                    .padding(.horizontal, 24).padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: visible)
        .allowsHitTesting(false)
        .onChange(of: message, initial: true) { _, value in
            // Autosave neither repeats nor cancels an explicit confirmation.
            guard !Self.quiet.contains(value), !value.isEmpty else { return }
            visible = value; notification = UUID()
        }
        .task(id: notification) {
            guard visible != nil else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            visible = nil
        }
    }
}

@MainActor
struct EditorSaveStatus: View {
    let message: String
    let dirty: Bool
    let busy: Bool
    let save: () -> Void
    @State private var expanded = false

    var body: some View {
        Button { expanded = true } label: {
            Group {
                if busy { ProgressView().controlSize(.small) }
                else { Image(systemName: dirty ? "circle.dotted" : "checkmark.circle").foregroundStyle(.secondary) }
            }.frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stato del quaderno")
        .accessibilityValue(busy ? "Operazione in corso" : dirty ? "Modifiche da salvare" : message)
        .accessibilityIdentifier("editorSaveStatus")
        .popover(isPresented: $expanded) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Stato del quaderno").font(.headline)
                Label(message, systemImage: dirty ? "circle.dotted" : "checkmark.circle")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Text("Gli appunti vengono salvati automaticamente sul dispositivo.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Salva adesso") { save() }.disabled(busy)
                    Spacer()
                    Button("Chiudi") { expanded = false }
                }.font(.subheadline.weight(.medium))
            }.padding(20).frame(idealWidth: 310, maxWidth: 360)
                .presentationCompactAdaptation(.popover)
        }
    }
}
