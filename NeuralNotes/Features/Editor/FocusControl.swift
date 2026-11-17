import SwiftUI
import NeuralNotesCore

@MainActor
struct FocusControl: View {
    @Bindable var model: EditorViewModel
    @Binding var focus: Bool
    let openStudy: () -> Void
    @State private var expanded = false
    var body: some View {
        HStack(spacing: 4) {
            if focus {
                if expanded {
                    ScrollView(.horizontal, showsIndicators: false) {
                        expandedTools
                    }.frame(maxWidth: CGFloat(model.currentWorkspace.effectiveFocusTools.count * 48 + 76 + (model.tool == .objects ? 48 : 0)))
                }
                Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                    Image(systemName: expanded ? "chevron.compact.right" : "pencil.tip.crop.circle").frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }.accessibilityLabel(expanded ? "Riduci strumenti essenziali" : "Strumenti essenziali").accessibilityIdentifier("editorMiniToolbar")
            }
            Button { withAnimation(.easeInOut(duration: 0.25)) { focus.toggle(); expanded = false } } label: {
                Image(systemName: focus ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }.accessibilityLabel(focus ? "Mostra strumenti" : "Solo foglio").accessibilityIdentifier("editorFocus")
        }
        .padding(4)
        .font(.system(size: 17, weight: .medium)).buttonStyle(.plain)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().stroke(.gray.opacity(0.25)).allowsHitTesting(false) }
        .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
        .onChange(of: focus) { _, value in if !value { expanded = false } }
    }

    private var expandedTools: some View {
        HStack(spacing: 4) {
            ForEach(model.currentWorkspace.effectiveFocusTools, id: \.self) { item in
                FocusToolButton(model: model, item: item)
            }
            if model.tool == .objects { FocusSelectionActions(model: model) }
            Button(action: openStudy) {
                Image(systemName: "point.3.connected.trianglepath.dotted").frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }.accessibilityLabel("Studio").accessibilityIdentifier("focusStudyKit")
            FocusToolsMenu(model: model)
        }
    }
}

@MainActor
struct FocusToolsMenu: View {
    @Bindable var model: EditorViewModel
    var showLabel = false
    var body: some View {
        Menu {
            ForEach(WorkspaceTool.allCases, id: \.self) { item in
                let selected = model.currentWorkspace.effectiveFocusTools.contains(item)
                Button {
                    model.editWorkspace { profile in
                        var tools = profile.effectiveFocusTools
                        if tools.contains(item) { if tools.count > 1 { tools.removeAll { $0 == item } } }
                        else if tools.count < EditorWorkspace.maximumFocusTools { tools.append(item) }
                        profile.focusTools = tools
                    }
                } label: { Label(item.title, systemImage: selected ? "checkmark.circle.fill" : item.icon) }
                    .disabled(selected ? model.currentWorkspace.effectiveFocusTools.count <= 1 : model.currentWorkspace.effectiveFocusTools.count >= EditorWorkspace.maximumFocusTools)
            }
            Button("Usa i primi tre preferiti") { model.editWorkspace { $0.focusTools = nil } }
        } label: {
            if showLabel { Label("Strumenti per Solo foglio", systemImage: "arrow.up.left.and.arrow.down.right") }
            else { Image(systemName: "gearshape").frame(width: 36, height: 44) }
        }
        .accessibilityLabel("Personalizza mini toolbar").accessibilityIdentifier("focusToolsSettings")
    }
}

@MainActor
struct RecordingIndicator: View {
    @Bindable var audio: AudioController
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 6) {
                Circle().fill(audio.recording ? .red : Brand.accent).frame(width: 8, height: 8)
                if audio.recording { Text("REC \(Int(audio.elapsed) / 60):\(String(format: "%02d", Int(audio.elapsed) % 60))") }
                else { Text("Trascr. \(Int(audio.transcriptionProgress * 100))%") }
            }.font(.caption.weight(.semibold)).monospacedDigit().fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 64, minHeight: 44).padding(4)
                .background(.regularMaterial, in: Capsule()).overlay(Capsule().stroke(.gray.opacity(0.2)))
        }.buttonStyle(.plain).accessibilityLabel(audio.recording ? "Registrazione in corso" : "Trascrizione in corso")
            .accessibilityIdentifier("editorRecordingIndicator")
    }
}
