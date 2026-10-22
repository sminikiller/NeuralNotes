import UIKit
import PencilKit
import NeuralNotesCore

/// Colors of Lens notes, as in a pack of sticky notes.
enum LensNoteColor: String, CaseIterable, Identifiable {
    case yellow, blue, green, pink
    var id: String { rawValue }
    var title: String {
        switch self { case .yellow: return "Giallo"; case .blue: return "Azzurro"; case .green: return "Verde"; case .pink: return "Rosa" }
    }
    var ink: InkColor {
        switch self {
        case .yellow: return InkColor(1, 0.94, 0.55); case .blue: return InkColor(0.8, 0.91, 1)
        case .green: return InkColor(0.82, 0.95, 0.78); case .pink: return InkColor(1, 0.85, 0.9)
        }
    }
    init(_ color: InkColor?) { self = Self.allCases.first { $0.ink == color } ?? .yellow }
}

/// The look of a Lens note: bold title, the answer with its paragraphs, bullet lists,
/// numbered steps and bold key terms, then a small italic origin line.
@MainActor
enum LensNoteStyle {
    /// Notes on a PDF page follow the size of its text, smaller than on paper pages.
    static func scale(for page: PageSnapshot) -> CGFloat {
        page.pdfFile == nil ? 1 : max(0.72, min(1, CGFloat(page.width) / 768))
    }

    static func text(title: String, body: String, origin: String?, scale: CGFloat = 1) -> NSAttributedString {
        let rich = NSMutableAttributedString(string: "")
        let size = 14 * scale
        func add(_ string: String, font: UIFont, color: UIColor = .black, style: NSParagraphStyle) {
            rich.append(NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]))
        }
        func newline() { if rich.length > 0 { add("\n", font: UIFont.systemFont(ofSize: size), style: paragraph(indent: 0, scale: scale)) } }
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !heading.isEmpty { add(heading, font: UIFont.boldSystemFont(ofSize: 15 * scale), style: paragraph(indent: 0, scale: scale)) }
        for block in LensMarkup.blocks(body) {
            newline()
            switch block {
            case .paragraph(let spans):
                runs(spans, size: size, bold: false, style: paragraph(indent: 0, scale: scale), into: rich)
            case .heading(let spans):
                runs(spans, size: size, bold: true, style: paragraph(indent: 0, scale: scale), into: rich)
            case .bullet(let spans):
                let style = paragraph(indent: 14 * scale, scale: scale)
                add("•\t", font: UIFont.systemFont(ofSize: size), style: style)
                runs(spans, size: size, bold: false, style: style, into: rich)
            case .numbered(let marker, let spans):
                let style = paragraph(indent: 20 * scale, scale: scale)
                add(marker + "\t", font: UIFont.systemFont(ofSize: size), style: style)
                runs(spans, size: size, bold: false, style: style, into: rich)
            }
        }
        if let origin, !origin.isEmpty {
            newline()
            add(origin, font: UIFont.italicSystemFont(ofSize: 11 * scale), color: .darkGray, style: paragraph(indent: 0, scale: scale))
        }
        return rich
    }

    /// Lists hang their text after the bullet, so wrapped lines stay aligned.
    private static func paragraph(indent: CGFloat, scale: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 3 * scale
        if indent > 0 {
            style.headIndent = indent; style.defaultTabInterval = indent
            style.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
        }
        return style
    }

    private static func runs(_ spans: [LensMarkup.Span], size: CGFloat, bold: Bool, style: NSParagraphStyle, into rich: NSMutableAttributedString) {
        for span in spans {
            let attributes: [NSAttributedString.Key: Any] = [.font: font(size: size, bold: bold || span.bold, italic: span.italic),
                                                             .foregroundColor: UIColor.black, .paragraphStyle: style]
            rich.append(NSAttributedString(string: span.text, attributes: attributes))
        }
    }

    static func font(size: CGFloat, bold: Bool, italic: Bool) -> UIFont {
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let base = UIFont.systemFont(ofSize: size)
        guard !traits.isEmpty, let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}

/// Which part of a Lens note a touch hit.
enum LensNotePart { case control, badge, body }

@MainActor
extension EditorViewModel {
    func requestLens(text: String? = nil, area: CGRect? = nil, compact: Bool = false) {
        guard hasLease, !loading, !navigating, !hasActiveStroke else { return }
        finishInkGesture(); endTextEdit()
        let selected = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        lensTextSelection = selected?.isEmpty == false ? String(selected!.prefix(8000)) : nil
        lensArea = area; lensPrefersPopup = compact; lensTab = .page; lensRequest += 1
    }
    @discardableResult
    func insertAIAnswer(_ artifact: AIArtifact) -> Bool {
        guard hasLease, !loading, !navigating, !hasActiveStroke, let current = page else { return false }
        let color: UIColor = current.appearance?.tone == .slate && current.pdfFile == nil ? .white : .black
        let rich = NSMutableAttributedString(string: "")
        if (artifact.webSources ?? []).isEmpty {
            rich.append(LensNoteStyle.text(title: "", body: artifact.text, origin: nil, scale: CGFloat(16) / 14))
            rich.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: rich.length))
        } else { for run in artifact.citedRuns {
            var attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: color]
            if let link = run.link { attributes[.link] = link; attributes[.foregroundColor] = UIColor.systemBlue; attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            rich.append(NSAttributedString(string: run.text, attributes: attributes))
        } }
        // Beside the circled area or the selection, clear of typed notes, images and ink.
        let selection = selectionBounds
        let anchor = lensArea ?? (selection.isNull ? nil : selection)
        let frame = LensGeometry.placement(text: rich.string, near: anchor, occupied: occupiedRects(current), pageWidth: current.width, pageHeight: current.height)
        var text = TextElement(text: rich.string); text.fontSize = 16; text.rtf = RichText.data(rich)
        text.x = Double(frame.minX); text.y = Double(frame.minY); text.width = Double(frame.width)
        mutatePage("Inserisci risposta AI con fonti") { $0.texts.append(text) }
        return page?.texts.contains(where: { $0.id == text.id }) == true
    }

    /// "Spiega e annota": a sticky note beside the underlined term, marked as general
    /// knowledge of the model; one undo removes it.
    @discardableResult
    func insertTermNote(_ value: TermExplanation, near area: CGRect?) -> Bool {
        insertLensNote(value, near: area) != nil
    }

    /// A Lens note beside the text it explains, linked to it. When the answer is long
    /// or there is no free room beside the text, the note starts as a 💡 icon there.
    @discardableResult
    func insertLensNote(_ value: TermExplanation, title: String? = nil, near area: CGRect?, useSelection: Bool = true) -> UUID? {
        guard hasLease, !loading, !navigating, !hasActiveStroke, let current = page else { return nil }
        let heading = String((title ?? value.term).prefix(200))
        let scale = LensNoteStyle.scale(for: current)
        let rich = LensNoteStyle.text(title: heading, body: value.noteBody, origin: value.origin, scale: scale)
        let selection = selectionBounds
        let anchor = area ?? (useSelection && !selection.isNull ? selection : nil)
        let occupied = occupiedRects(current)
        let spot = LensGeometry.placementResult(text: rich.string, near: anchor, occupied: occupied, pageWidth: current.width, pageHeight: current.height,
                                                fontSize: Double(14 * scale), maximumWidth: 260 * scale)
        let reduce = !spot.clear || Double(spot.rect.height) > current.height * 0.35
        var text = TextElement(text: rich.string); text.fontSize = Double(14 * scale); text.rtf = RichText.data(rich)
        text.background = LensNoteColor.yellow.ink; text.width = Double(spot.rect.width)
        let origin = reduce ? LensNotes.badgePlacement(near: anchor, occupied: occupied, pageWidth: current.width, pageHeight: current.height).origin : spot.rect.origin
        text.x = Double(origin.x); text.y = Double(origin.y)
        text.lensNote = LensNoteInfo(title: heading, origin: value.origin, source: anchor.map { LensNoteSource(pageID: current.id, rect: $0) },
                                     collapsed: reduce, createdAt: Date().timeIntervalSince1970)
        mutatePage("Inserisci nota della Lente") { $0.texts.append(text) }
        return page?.texts.contains(where: { $0.id == text.id }) == true ? text.id : nil
    }

    /// The Lens note under a touch: its reduce control, its icon or its body.
    func lensNoteHit(at point: CGPoint, tolerance: CGFloat) -> (id: UUID, part: LensNotePart)? {
        guard let page else { return nil }
        for text in page.texts.reversed() {
            guard let note = text.lensNote else { continue }
            let box = RichText.bounds(text, pageHeight: page.height)
            if note.isCollapsed {
                if LensNotes.hitRect(box, zoom: Double(canvas.zoomScale), slack: Double(tolerance)).contains(point) { return (text.id, LensNotePart.badge) }
                continue
            }
            let control = LensNotes.reduceControl(note: box, pageWidth: page.width, pageHeight: page.height)
            if LensNotes.hitRect(control, zoom: Double(canvas.zoomScale), slack: Double(tolerance)).contains(point) { return (text.id, LensNotePart.control) }
            if box.insetBy(dx: -8, dy: -8).contains(point) { return (text.id, LensNotePart.body) }
        }
        return nil
    }

    /// Reduces a Lens note to its icon or opens it again, inside the page.
    func setLensNote(_ id: UUID, collapsed: Bool) {
        guard let current = page, var text = current.texts.first(where: { $0.id == id }), text.lensNote != nil,
              text.lensNote?.isCollapsed != collapsed else { return }
        text.lensNote?.collapsed = collapsed ? true : nil
        if !collapsed {
            let origin = LensNotes.opened(RichText.bounds(text, pageHeight: current.height), pageWidth: current.width, pageHeight: current.height)
            text.x = Double(origin.x); text.y = Double(origin.y)
        }
        let value = text
        mutatePage(collapsed ? "Riduci nota" : "Apri nota") { page in
            if let i = page.texts.firstIndex(where: { $0.id == id }) { page.texts[i] = value }
        }
    }

    func setAllLensNotes(collapsed: Bool) {
        guard let current = page else { return }
        var texts = current.texts
        for i in texts.indices where texts[i].lensNote != nil && texts[i].lensNote?.isCollapsed != collapsed {
            texts[i].lensNote?.collapsed = collapsed ? true : nil
            if !collapsed {
                let origin = LensNotes.opened(RichText.bounds(texts[i], pageHeight: current.height), pageWidth: current.width, pageHeight: current.height)
                texts[i].x = Double(origin.x); texts[i].y = Double(origin.y)
            }
        }
        guard texts != current.texts else { return }
        let values = texts
        mutatePage(collapsed ? "Riduci le note" : "Apri le note") { $0.texts = values }
    }

    /// Saves a note edited by the student: title, text, color and icon state.
    func updateLensNote(_ id: UUID, title: String, body: String, color: LensNoteColor, collapsed: Bool) {
        guard let current = page, var text = current.texts.first(where: { $0.id == id }), var note = text.lensNote else { return }
        let heading = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        note.title = heading.isEmpty ? note.title : heading
        let rich = LensNoteStyle.text(title: note.title, body: body, origin: note.origin, scale: LensNoteStyle.scale(for: current))
        text.text = rich.string; text.rtf = RichText.data(rich); text.background = color.ink
        note.collapsed = collapsed ? true : nil; text.lensNote = note
        if !collapsed {
            let origin = LensNotes.opened(RichText.bounds(text, pageHeight: current.height), pageWidth: current.width, pageHeight: current.height)
            text.x = Double(origin.x); text.y = Double(origin.y)
        }
        let value = text
        mutatePage("Modifica nota della Lente") { page in
            if let i = page.texts.firstIndex(where: { $0.id == id }) { page.texts[i] = value }
        }
    }

    /// Saves a note edited with the formatting tools: its text and style as typed, the
    /// first line as its title in the list, color and icon state.
    func updateLensNote(_ id: UUID, edited: TextElement, color: LensNoteColor, collapsed: Bool) {
        guard let current = page, var text = current.texts.first(where: { $0.id == id }), var note = text.lensNote else { return }
        text.text = edited.text; text.rtf = edited.rtf; text.background = color.ink
        let first = edited.text.split(separator: "\n").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        if !first.isEmpty { note.title = String(first.prefix(200)) }
        note.collapsed = collapsed ? true : nil; text.lensNote = note
        if !collapsed {
            let origin = LensNotes.opened(RichText.bounds(text, pageHeight: current.height), pageWidth: current.width, pageHeight: current.height)
            text.x = Double(origin.x); text.y = Double(origin.y)
        }
        let value = text
        mutatePage("Modifica nota della Lente") { page in
            if let i = page.texts.firstIndex(where: { $0.id == id }) { page.texts[i] = value }
        }
    }

    func deleteLensNote(_ id: UUID, pageID: UUID) async {
        guard await focusLensNote(id, pageID: pageID, outline: false) else { return }
        mutatePage("Elimina nota della Lente") { $0.texts.removeAll { $0.id == id } }
        if selectedIDs.contains(id) { selectedObjectID = nil }
    }

    func toggleLensNote(_ id: UUID, pageID: UUID) async {
        guard await focusLensNote(id, pageID: pageID, outline: false),
              let collapsed = page?.texts.first(where: { $0.id == id })?.lensNote?.isCollapsed else { return }
        setLensNote(id, collapsed: !collapsed)
    }

    /// Opens the page of a note, brings the note (or the text it explains) to the
    /// middle of the screen and outlines it for a moment.
    @discardableResult
    func focusLensNote(_ id: UUID, pageID: UUID? = nil, source: Bool = false, outline: Bool = true) async -> Bool {
        var found = pageID
        if found == nil, page?.texts.contains(where: { $0.id == id }) == true { found = page?.id }
        if found == nil { found = pages.first(where: { candidate in candidate.texts.contains { $0.id == id } })?.id }
        guard let owner = found else { error = "Nota non trovata: forse è stata eliminata."; return false }
        if page?.id != owner {
            guard let target = pages.first(where: { $0.id == owner }) else { error = "La pagina della nota è stata rimossa."; return false }
            await select(target)
        }
        guard let current = page, current.id == owner, let text = current.texts.first(where: { $0.id == id }) else {
            if page?.id == owner { error = "Nota non trovata: forse è stata eliminata." }
            return false
        }
        var rect = RichText.bounds(text, pageHeight: current.height)
        if source, let origin = text.lensNote?.source {
            if origin.pageID != current.id, let target = pages.first(where: { $0.id == origin.pageID }) {
                await select(target)
                guard page?.id == origin.pageID else { return false }
            }
            rect = origin.rect
        }
        guard outline, let shown = page else { return true }
        let focus = LensNoteFocus(pageID: shown.id, rect: rect)
        lensNoteFocus = focus
        Task { [weak self] in
            // The page may still be laying out after a switch: center once it settled.
            try? await Task.sleep(for: .milliseconds(180))
            (self?.pagePresenter as? CanvasHost)?.centerWritingArea(CGPoint(x: rect.midX, y: rect.midY), zoomFactor: 1.4)
            try? await Task.sleep(for: .seconds(2.5))
            if self?.lensNoteFocus == focus { self?.lensNoteFocus = nil }
        }
        return true
    }

    /// Redraws the Lens helpers on the page after a pick, a highlight or a jump changed.
    func refreshLensOverlays() {
        guard let host = pagePresenter as? CanvasHost else { return }
        host.lensNotes.update(host); host.lensBar.update(host)
    }

    /// "Chiedi ancora": a new conversation about the subject of a note.
    func askLensAgain(_ id: UUID) {
        guard let current = page, let text = current.texts.first(where: { $0.id == id }), let note = text.lensNote else { return }
        let area = note.source.flatMap { $0.pageID == current.id ? $0.rect : nil }
        lensAnchor = nil
        openLens(LensCardRequest(area: area, text: note.title))
    }

    private func occupiedRects(_ current: PageSnapshot) -> [CGRect] {
        var occupied = current.texts.map { RichText.bounds($0, pageHeight: current.height) }
        occupied += current.images.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        occupied += (current.shapes ?? []).map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        occupied += canvas.drawing.strokes.map(\.renderBounds)
        return occupied
    }
}
