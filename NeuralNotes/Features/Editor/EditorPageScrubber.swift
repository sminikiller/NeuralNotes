import SwiftUI
import NeuralNotesCore

/// Only the final release opens a page, even in a 1,500-page notebook.
@MainActor
struct EditorPageScrubber: View {
    let pageIDs: [UUID]
    let currentIndex: Int
    let select: (Int) -> Void
    @GestureState private var preview: Int?
    @Environment(\.layoutDirection) private var direction

    private let thumb: CGFloat = 16
    private var displayedIndex: Int { preview ?? currentIndex }

    var body: some View {
        GeometryReader { geometry in
            let travel = max(1, geometry.size.width - thumb)
            let unit = PageScrubberPosition.fraction(index: displayedIndex, count: pageIDs.count)
            let x = thumb / 2 + CGFloat(direction == .rightToLeft ? 1 - unit : unit) * travel
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.12)).frame(height: preview == nil ? 3 : 6)
                    .padding(.horizontal, thumb / 2)
                Circle().fill(Brand.accent).frame(width: thumb, height: thumb)
                    .scaleEffect(preview == nil ? 0.75 : 1.2)
                    .position(x: x, y: geometry.size.height / 2)
            }
            .frame(height: geometry.size.height)
            .contentShape(Rectangle())
            .overlay(alignment: .topLeading) {
                if preview != nil {
                    Text("\(displayedIndex + 1) / \(pageIDs.count)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().stroke(.primary.opacity(0.12)))
                        .fixedSize()
                        .position(x: min(max(54, x), max(54, geometry.size.width - 54)), y: -20)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .updating($preview) { value, state, _ in
                    state = target(value.location.x, travel: travel)
                }
                .onEnded { value in
                    if let index = target(value.location.x, travel: travel) { select(index) }
                })
            .animation(.easeOut(duration: 0.12), value: preview != nil)
        }
        .frame(minWidth: 60, minHeight: 44, maxHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scorri le pagine")
        .accessibilityValue("Pagina \(currentIndex + 1) di \(pageIDs.count)")
        .accessibilityHint("Trascina e rilascia per aprire una pagina. Regolabile con VoiceOver.")
        .accessibilityAdjustableAction { adjustment in
            let offset: Int
            switch adjustment { case .increment: offset = 1; case .decrement: offset = -1; @unknown default: return }
            let next = min(pageIDs.count - 1, max(0, currentIndex + offset))
            if next != currentIndex { select(next) }
        }
        .accessibilityIdentifier("editorPageScrubber")
        // Cancels an unfinished drag if the document's page order changes.
        .id(pageIDs)
    }

    private func target(_ x: CGFloat, travel: CGFloat) -> Int? {
        let unit = Double((x - thumb / 2) / travel)
        return PageScrubberPosition.index(fraction: direction == .rightToLeft ? 1 - unit : unit, count: pageIDs.count)
    }
}

@MainActor
struct PageJumpPopover: View {
    let count: Int
    let currentIndex: Int
    let select: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Vai alla pagina").font(.headline)
                Spacer()
                Button("Chiudi", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
            }
            HStack(spacing: 12) {
                TextField("Numero", text: $number).keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder).onSubmit(jump)
                    .accessibilityIdentifier("editorPageNumber")
                Text("di \(count)").foregroundStyle(.secondary).font(.subheadline)
                Button("Vai", action: jump).buttonStyle(.borderedProminent)
                    .disabled(PageScrubberPosition.pageNumber(number, count: count) == nil)
                    .accessibilityIdentifier("editorJumpConfirm")
            }
            Text("Trascina la barra per sfogliare rapidamente; la pagina si apre al rilascio.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(idealWidth: 320, maxWidth: 360)
        .onAppear { number = "\(currentIndex + 1)" }
        .presentationCompactAdaptation(.popover)
    }

    private func jump() {
        guard let index = PageScrubberPosition.pageNumber(number, count: count) else { return }
        dismiss(); select(index)
    }
}
