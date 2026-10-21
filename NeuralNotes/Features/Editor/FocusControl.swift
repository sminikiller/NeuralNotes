import SwiftUI
import NeuralNotesCore

@MainActor
struct FocusControl: View {
    @Bindable var model: EditorViewModel
    @Binding var focus: Bool
    @SceneStorage("focus.position.x") private var savedX = 0.0
    @SceneStorage("focus.position.y") private var savedY = 0.0
    @GestureState private var translation = CGSize.zero
    @State private var expanded = false
    var body: some View {
        GeometryReader { geometry in
            let toolsWidth = CGFloat(model.currentWorkspace.effectiveFocusTools.count * 48 + 192)
            let width: CGFloat = min(max(48, geometry.size.width - 24), !focus ? 48 : expanded ? toolsWidth : 102)
            let right = max(width + 12, min(geometry.size.width - 12, geometry.size.width - 12 + CGFloat(savedX) + translation.width))
            let y = max(36, min(geometry.size.height - 36, 36 + CGFloat(savedY) + translation.height))
            HStack(spacing: 4) {
                if focus {
                    if expanded {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                        ForEach(model.currentWorkspace.effectiveFocusTools, id: \.self) { item in
                            Button { model.chooseTool(item) } label: { Image(systemName: item.icon).frame(width: 44, height: 44) }
                                .accessibilityLabel(item.title).accessibilityIdentifier("focusTool-\(item.rawValue)")
                        }
                        Button { Task { await model.performUndo() } } label: { Image(systemName: "arrow.uturn.backward").frame(width: 36, height: 44) }
                            .disabled(!model.canUndo).accessibilityLabel("Annulla")
                        FocusToolsMenu(model: model)
                            }
                        }.frame(maxWidth: .infinity)
                    }
                    Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                        Image(systemName: expanded ? "chevron.compact.right" : "pencil.tip.crop.circle").frame(width: 44, height: 44)
                    }.accessibilityLabel(expanded ? "Riduci strumenti essenziali" : "Strumenti essenziali").accessibilityIdentifier("editorMiniToolbar")
                }
                Button { withAnimation(.easeInOut(duration: 0.25)) { focus.toggle(); expanded = false } } label: {
                    Image(systemName: focus ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").frame(width: 48, height: 48)
                        .overlay(alignment: .topTrailing) { if model.audio?.recording == true { Circle().fill(.red).frame(width: 8, height: 8).padding(4) } }
                }.accessibilityLabel(focus ? "Mostra strumenti" : "Solo foglio").accessibilityIdentifier("editorFocus")
            }
            .font(.system(size: 17, weight: .medium)).buttonStyle(.plain)
            .frame(width: width, height: 48)
            .background(.regularMaterial, in: Capsule()).overlay(Capsule().stroke(.gray.opacity(0.25)))
            .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
            .position(x: right - width / 2, y: y)
            .simultaneousGesture(DragGesture(minimumDistance: 14, coordinateSpace: .named("focus-area"))
                .updating($translation) { value, state, _ in state = value.translation }
                .onEnded { value in
                    savedX = max(-max(0, Double(geometry.size.width - width - 24)), min(0, savedX + Double(value.translation.width)))
                    savedY = max(0, min(max(0, Double(geometry.size.height - 72)), savedY + Double(value.translation.height)))
                })
        }.coordinateSpace(name: "focus-area")
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
                if audio.recording { Text("REC \(Int(audio.elapsed) / 60):\(String(format: "%02d", Int(audio.elapsed) % 60))").monospacedDigit() }
                else { Text("Trascrizione \(Int(audio.transcriptionProgress * 100))%") }
            }.font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule()).overlay(Capsule().stroke(.gray.opacity(0.2)))
        }.buttonStyle(.plain).accessibilityLabel(audio.recording ? "Registrazione in corso" : "Trascrizione in corso")
            .accessibilityIdentifier("editorRecordingIndicator")
    }
}
