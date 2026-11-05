import SwiftUI
import PencilKit
import NeuralNotesCore

enum HandwritingCommand: String, CaseIterable, Identifiable {
    case straighten = "Raddrizza", uniformSize = "Uniforma dimensione", cleanup = "Ripulisci tratto"
    case reflow = "Riadatta alla larghezza", spacing = "Spazio tra le righe"
    var id: String { rawValue }
}

@MainActor @Observable
final class HandwritingSession {
    let command: HandwritingCommand
    var preparing = true
    var message: String?
    var alignLeft = false
    var onPaperLines = false
    var strength: HandwritingCleanup.Strength = .medium
    var width: Double = 200
    var left: Double = 0
    var lineSpacing: Double = 1
    var previewToken = UUID()
    var proposal: HandwritingProposal?
    private var fitsRenderedPage = false
    @ObservationIgnored private(set) var preview: PKDrawing?
    @ObservationIgnored let original: PKDrawing
    @ObservationIgnored let ghost: PKDrawing
    @ObservationIgnored let before: EditorContentState
    @ObservationIgnored private(set) var input: HandwritingNative.Input?
    @ObservationIgnored private weak var model: EditorViewModel?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let generation: UUID
    @ObservationIgnored private var ticket = UUID()
    @ObservationIgnored private var pendingRecompute = false
    @ObservationIgnored private var cancelled = false
    let selected: Set<Int>

    init(command: HandwritingCommand, model: EditorViewModel, before: EditorContentState, selected: Set<Int>) {
        self.command = command; self.model = model; self.before = before; self.selected = selected
        let native = model.canvas.drawing, strokes = native.strokes
        original = native; generation = model.inkDisplayGeneration
        ghost = PKDrawing(strokes: selected.sorted().compactMap { index in
            guard strokes.indices.contains(index), strokes[index].ink.inkType != .marker else { return nil }
            return strokes[index]
        })
    }
    var isCurrent: Bool {
        guard !cancelled, let model, model.handwriting === self else { return false }
        return model.hasLease && !model.loading && !model.navigating && model.canEditActiveLayer &&
            model.page?.id == before.page.id && model.drawingLayerID == (before.layerID ?? before.page.id) &&
            model.inkDisplayGeneration == generation && !model.inkReplayActive
    }
    var canApply: Bool { !preparing && proposal?.fitsPage == true && fitsRenderedPage && preview != nil && isCurrent }
    var selectionBounds: CGRect {
        guard let bounds = proposal?.bounds ?? input?.analysis.bounds else { return .null }
        return CGRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height)
    }
    var minimumWidth: Double { max(20, input?.analysis.lines.flatMap(\.words).map { $0.bounds.width }.max() ?? 20) }
    var maximumWidth: Double { max(minimumWidth, before.page.width - left - 8) }

    func start() {
        guard let data = before.drawing else { message = HandwritingFailure.invalidSelection.localizedDescription; preparing = false; return }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let selected = self.selected
                let hints = PageWordIndex.shared.handwritingLineHints(before.page)
                let worker = Task.detached(priority: .userInitiated) { try HandwritingNative.analyze(data, selected: selected, lineHints: hints) }
                let input = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                guard isCurrent else { model?.cancelHandwriting(); return }
                self.input = input; left = input.analysis.bounds.x
                width = min(maximumWidth, max(minimumWidth, input.analysis.bounds.width)); task = nil
                recompute()
            } catch is CancellationError { }
            catch { message = error.localizedDescription; preparing = false }
        }
    }
    func recompute() {
        guard let input, isCurrent else { return }
        // Coalesce changes while one worker is running. A trailing debounce
        // alone would show no reflow until the finger stopped moving.
        if task != nil { pendingRecompute = true; return }
        pendingRecompute = false
        preparing = true; message = nil
        let current = UUID(); ticket = current
        let action: HandwritingAction
        switch command {
        case .straighten: action = .straighten
        case .uniformSize: action = .uniformSize
        case .cleanup: action = .cleanup(strength)
        case .reflow: action = .reflow(width: width)
        case .spacing: action = .lineSpacing(lineSpacing)
        }
        var options = HandwritingOptions(); options.alignLeft = alignLeft; options.reflowX = left
        if onPaperLines && before.page.paper == .ruled { options.paperSpacing = before.page.appearance?.spacing ?? 32 }
        let bounds = SnapRect(x: 0, y: 0, width: before.page.width, height: before.page.height)
        task = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(33))
                let configuration = options
                let worker = Task.detached(priority: .userInitiated) {
                    try HandwritingLayout.propose(action, strokes: input.strokes, analysis: input.analysis, page: bounds, options: configuration)
                }
                let proposal = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                guard let self, ticket == current else { return }
                guard isCurrent else { model?.cancelHandwriting(); return }
                let next = try HandwritingNative.applying(proposal, to: original, allowed: selected)
                let native = next.strokes
                let painted = proposal.adjustments.reduce(CGRect.null) { $0.union(native[$1.strokeID].renderBounds) }
                let sheet = CGRect(x: 0, y: 0, width: before.page.width, height: before.page.height).insetBy(dx: -0.5, dy: -0.5)
                fitsRenderedPage = !painted.isNull && !painted.isInfinite && sheet.contains(painted)
                self.proposal = proposal; preview = next; previewToken = UUID(); preparing = false
                if !proposal.fitsPage || !fitsRenderedPage { message = HandwritingFailure.outsidePage.localizedDescription }
                (model?.pagePresenter as? CanvasHost)?.handwritingPreview.update()
                task = nil
                if pendingRecompute { recompute() }
            } catch is CancellationError { }
            catch {
                guard let self, ticket == current else { return }
                message = error.localizedDescription; preparing = false; proposal = nil; task = nil
                if pendingRecompute { recompute() }
            }
        }
    }
    func cancel() { cancelled = true; task?.cancel(); task = nil; pendingRecompute = false; ticket = UUID(); preview = nil }
    func apply() {
        guard canApply, let model, let preview, let current = model.captureEdit(ink: false),
              current.normalized == before.normalized, NativeInkComparison.equal(model.canvas.drawing, original) else {
            message = "Gli appunti sono cambiati. Annulla l’anteprima e selezionali di nuovo."; return
        }
        let metadata = (try? JSONEncoder().encode(before.page).count) ?? 0
        let cost = (before.drawing?.count ?? 0) + preview.dataRepresentation().count + metadata * 2
        guard model.history.accepts(cost: cost) else { message = HandwritingFailure.tooLarge.localizedDescription; return }
        model.cancelHandwriting()
        guard !NativeInkComparison.equal(preview, original) else { model.status = "La grafia è già regolare"; return }
        model.installNativeInk(preview)
        model.recordEdit(before, label: command.rawValue)
        // Recognized text is content, not geometry. Keep it; invalidate its
        // old spatial index so future Pencil hits never use obsolete boxes.
        model.drawingChanged()
        (model.pagePresenter as? CanvasHost)?.interaction?.refresh()
    }
}

@MainActor extension EditorViewModel {
    var canRefineHandwriting: Bool {
        guard selectionIncludesInk, canEditActiveLayer, !inkReplayActive, !interactionBusy else { return false }
        return canvas.drawing.strokes.enumerated().contains { index, stroke in
            (selectedStrokeIndices?.contains(index) ?? true) && stroke.ink.inkType != .marker
        }
    }
    func beginHandwriting(_ command: HandwritingCommand) {
        finishInkGesture(); endTextEdit(); closeZoomWriting()
        guard canRefineHandwriting, hasLease, !navigating, !loading, let before = captureEdit(ink: true) else { return }
        let selected = selectedStrokeIndices ?? Set(canvas.drawing.strokes.indices)
        let session = HandwritingSession(command: command, model: self, before: before, selected: selected)
        handwriting = session; configureTool(); session.start()
    }
    func cancelHandwriting() {
        guard let session = handwriting else { return }
        session.cancel(); handwriting = nil
        (pagePresenter as? CanvasHost)?.handwritingPreview.update()
        configureTool()
    }
}

@MainActor struct HandwritingMenu: View {
    @Bindable var model: EditorViewModel
    var body: some View {
        Menu("Grafia", systemImage: "pencil.and.scribble") {
            ForEach(HandwritingCommand.allCases) { command in
                Button(command.rawValue) { model.beginHandwriting(command) }
            }
        }.disabled(!model.canRefineHandwriting).accessibilityIdentifier("handwritingMenu")
    }
}

@MainActor struct HandwritingPanel: View {
    @Bindable var session: HandwritingSession
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(session.command.rawValue, systemImage: "pencil.and.scribble").font(.headline)
                Spacer(); if session.preparing { ProgressView().controlSize(.small) }
            }
            options
            if let message = session.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Text("Anteprima · originali sbiaditi").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Annulla", action: cancel).accessibilityIdentifier("handwritingCancel")
                Button("Applica") { session.apply() }.buttonStyle(.borderedProminent).tint(Brand.accent)
                    .disabled(!session.canApply).accessibilityIdentifier("handwritingApply")
            }
        }.padding(14).frame(maxWidth: 480)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.15)))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4).padding(12)
            .accessibilityIdentifier("handwritingPanel")
            .onChange(of: session.alignLeft) { _, _ in session.recompute() }
            .onChange(of: session.onPaperLines) { _, _ in session.recompute() }
            .onChange(of: session.strength) { _, _ in session.recompute() }
            .onChange(of: session.width) { _, _ in session.recompute() }
            .onChange(of: session.lineSpacing) { _, _ in session.recompute() }
    }
    @ViewBuilder private var options: some View {
        switch session.command {
        case .straighten:
            Toggle("Allinea a sinistra", isOn: $session.alignLeft)
            if session.before.page.paper == .ruled { Toggle("Appoggia sulle righe", isOn: $session.onPaperLines) }
        case .cleanup:
            Picker("Intensità", selection: $session.strength) {
                Text("Leggera").tag(HandwritingCleanup.Strength.light)
                Text("Media").tag(HandwritingCleanup.Strength.medium)
                Text("Forte").tag(HandwritingCleanup.Strength.strong)
            }.pickerStyle(.segmented)
        case .reflow:
            Text("Trascina le maniglie ai lati oppure regola la larghezza.").font(.caption).foregroundStyle(.secondary)
            Slider(value: $session.width, in: session.minimumWidth...max(session.minimumWidth + 1, session.maximumWidth))
                .accessibilityLabel("Larghezza della grafia")
        case .spacing:
            HStack { Text("Interlinea"); Slider(value: $session.lineSpacing, in: 0.5...2); Text(session.lineSpacing, format: .number.precision(.fractionLength(1))).monospacedDigit() }
        case .uniformSize:
            Text("Dimensioni uniformi, con variazioni limitate al 20–25%.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
