import SwiftUI
import PencilKit
import NeuralNotesCore

extension InkTool {
    var workspaceTool: WorkspaceTool {
        switch self { case .pen: return .pen; case .marker: return .marker; case .eraser: return .eraser
        case .lasso: return .lasso; case .objects: return .objects; case .audioLink: return .audioLink; case .text: return .text; case .shape: return .line; case .lens: return .lens }
    }
}
extension InkColor {
    @MainActor var color: Color { Color(red: red, green: green, blue: blue) }
    @MainActor init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        PaperInk.color(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(Double(r), Double(g), Double(b))
    }
}
extension WorkspaceTool {
    var title: String {
        switch self { case .pen: return "Penna"; case .marker: return "Evidenziatore"; case .eraser: return "Gomma"
        case .lasso: return "Lazo"; case .objects: return "Oggetti"; case .text: return "Testo con Pencil"; case .audioLink: return "Ascolta tratto"
        case .line: return "Linea"; case .arrow: return "Freccia"; case .ellipse: return "Cerchio"; case .rectangle: return "Rettangolo"; case .triangle: return "Triangolo"; case .ruler: return "Righello"; case .lens: return "Lente AI" }
    }
    var icon: String {
        switch self { case .pen: return "pencil.tip"; case .marker: return "highlighter"; case .eraser: return "eraser"
        case .lasso: return "lasso"; case .objects: return "cursorarrow.and.square.on.square.dashed"; case .text: return "character.cursor.ibeam"
        case .audioLink: return "waveform"; case .line: return "line.diagonal"; case .arrow: return "arrow.up.right"
        case .ellipse: return "circle"; case .rectangle: return "rectangle"; case .triangle: return "triangle"; case .ruler: return "ruler"; case .lens: return "sparkle.magnifyingglass" }
    }
    var shape: ShapeKind? {
        switch self { case .line: return .line; case .arrow: return .arrow; case .ellipse: return .ellipse; case .rectangle: return .rectangle; case .triangle: return .triangle; default: return nil }
    }
}

@MainActor
extension EditorViewModel {
    var currentWorkspace: EditorWorkspace { workspaces.selected }
    var activePalette: ToolPalette { currentWorkspace.palette(for: tool.workspaceTool) }
    func editWorkspace(_ edit: (inout EditorWorkspace) -> Void) {
        guard let index = workspaces.profiles.firstIndex(where: { $0.id == workspaces.selectedID }) else { return }
        var state = workspaces; edit(&state.profiles[index]); guard state.isValid, state != workspaces else { return }
        workspaces = state; scheduleWorkspaceSave()
    }
    func selectWorkspace(_ id: UUID) {
        guard !interactionBusy, workspaces.profiles.contains(where: { $0.id == id }) else { return }
        workspaces.selectedID = id; rulerActive = false; canvas.isRulerActive = false
        chooseTool(currentWorkspace.favorites.first(where: { $0 != .ruler }) ?? .pen)
        scheduleWorkspaceSave()
    }
    func duplicateWorkspace(name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40, workspaces.profiles.count < 12 else { return }
        var value = currentWorkspace; value.id = UUID(); value.name = name
        workspaces.profiles.append(value); workspaces.selectedID = value.id; scheduleWorkspaceSave()
    }
    func deleteWorkspace() {
        guard workspaces.profiles.count > 1 else { return }
        let id = workspaces.selectedID
        workspaces.profiles.removeAll { $0.id == id }; selectWorkspace(workspaces.profiles[0].id)
    }
    func chooseTool(_ item: WorkspaceTool) {
        laserActive = false
        guard !hasActiveStroke else { return }
        cancelMaintenance()
        if item == .lens, tool != .lens { toolBeforeLens = tool }
        if item == .ruler {
            if tool != .pen && tool != .marker { tool = .pen; restoreToolPalette() }
            rulerActive.toggle(); configureTool(); return
        }
        if let shape = item.shape { shapeKind = shape; tool = .shape }
        else {
            switch item { case .pen: tool = .pen; case .marker: tool = .marker; case .eraser: tool = .eraser
            case .lasso: tool = .lasso; case .objects: tool = .objects; case .text: tool = .text; case .audioLink: tool = .audioLink; case .lens: tool = .lens; default: break }
        }
        restoreToolPalette(); configureTool()
        lensPick = nil; lensHighlight = nil
        if tool == .lens { prepareLensWords() }
    }
    func restoreToolPalette() {
        let palette = activePalette
        let style = tool == .shape ? shapePreferences.style : nil
        ink = (style?.color ?? palette.recentColors.first ?? palette.favorites.first ?? .black).color
        thickness = style?.width ?? palette.recentWidths.first ?? 3
    }
    func chooseInk(_ color: Color) { guard !hasActiveStroke else { return }; ink = color; rememberPalette(); configureTool() }
    func chooseWidth(_ value: Double) { guard !hasActiveStroke else { return }; thickness = value; rememberPalette(); configureTool() }
    func rememberPalette() {
        let item = tool.workspaceTool, color = InkColor(ink), width = thickness
        editWorkspace { profile in
            var palette = profile.palette(for: item); palette.use(color: color, width: width); profile.palettes[item.rawValue] = palette
        }
    }
    func toggleFavoriteColor() {
        let item = tool.workspaceTool, color = InkColor(ink)
        editWorkspace { profile in
            var palette = profile.palette(for: item)
            if palette.favorites.contains(color) { palette.favorites.removeAll { $0 == color } }
            else { palette.favorites = Array((palette.favorites + [color]).suffix(6)) }
            profile.palettes[item.rawValue] = palette
        }
    }
    func scheduleWorkspaceSave() {
        workspaceSettingsDirty = true; workspaceSaveTask?.cancel()
        workspaceSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            _ = await self?.saveWorkspaceSettings()
        }
    }
    func saveWorkspaceSettings() async -> Bool {
        while hasLease && workspaceSettingsDirty {
            let settings = workspaces
            do {
                try await workspace.setEditorWorkspaces(settings)
                if workspaces == settings { workspaceSettingsDirty = false }
            } catch {
                self.error = error.localizedDescription
                status = dirty ? "Modifiche da salvare · errore impostazioni" : "Pagina salvata · impostazioni da recuperare"
                return false
            }
        }
        return true
    }

    var canRecoverCatalog: Bool {
        hasLease && !loading && !navigating && !hasActiveStroke && audio?.recording != true
            && audio?.transitioning != true && audio?.transcribingSessionID == nil
    }

    /// The owning editor may recover without closing: a settings failure can
    /// otherwise prevent close(), making library-only recovery unreachable.
    func recoverCatalog() async -> Bool {
        guard canRecoverCatalog else { return false }
        navigating = true; defer { navigating = false }
        _ = await flush()
        guard !dirty, !saving, !hasActiveStroke else { return false }
        do {
            let recovery = try await workspace.catalogRecoveryStatus()
            guard recovery.needsRecovery, recovery.canRestore else { return false }
            try await workspace.restorePreviousCatalog()
            // Retain the latest audio metadata still held by this sole writer,
            // including a paused recording whose last checkpoint failed.
            var sessions = audio?.sessions ?? []
            if let active = audio?.active {
                sessions.removeAll { $0.id == active.id }; sessions.append(active)
            }
            let restored = try await workspace.catalog()
            for var session in sessions {
                let storedRevision = restored.sessions.first(where: { $0.id == session.id })?.revision ?? 0
                session.revision = max(storedRevision, session.revision ?? 0) + 1
                try await workspace.saveSession(session)
                if audio?.active?.id == session.id { audio?.active = session }
            }
            if let audio { audio.sessions = try await workspace.catalog().sessions; audio.error = nil }
            if page != nil {
                workspaceSettingsDirty = true
                guard await saveWorkspaceSettings() else { return false }
            } else {
                await open()
                guard page != nil else { return false }
            }
            error = nil; status = "Catalogo recuperato · pagina conservata"
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
