import SwiftUI
import NeuralNotesCore

enum Brand {
    #if SWIFT_PACKAGE
    static let accent = Color("AccentColor", bundle: .module)
    #else
    static let accent = Color("AccentColor")
    #endif
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
}

extension NotebookCover {
    var color: Color {
        switch self {
        case .midnight: return Color(red: 0.14, green: 0.20, blue: 0.32)
        case .lagoon: return Color(red: 0.10, green: 0.40, blue: 0.39)
        case .terracotta: return Color(red: 0.64, green: 0.30, blue: 0.22)
        case .lavender: return Color(red: 0.39, green: 0.32, blue: 0.56)
        case .sand: return Color(red: 0.52, green: 0.41, blue: 0.25)
        }
    }
}

@MainActor
struct NotebookCoverView: View {
    let notebook: Notebook
    var compact = false
    var photo: UIImage? = nil
    var design: CoverDesign? = nil
    var isPagePreview = false
    private var appearance: CoverDesign { design ?? .suggested(id: notebook.id, title: notebook.title) }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: compact ? 8 : 16)
                .fill((appearance.color?.color ?? notebook.cover.color).gradient)
            CoverDecoration(pattern: appearance.pattern).clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 16))
            Rectangle().fill(.black.opacity(0.16))
                .frame(width: compact ? 5 : 12).padding(.leading, compact ? 5 : 12)
            if compact {
                Image(systemName: appearance.symbol).foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: appearance.symbol).font(.system(size: 30, weight: .light))
                    Spacer(minLength: 12)
                    Text(notebook.title).font(.title3.weight(.semibold)).lineLimit(3)
                    Text("NEURALNOTES").font(.caption2.weight(.medium)).tracking(2)
                }
                .foregroundStyle(.white).padding(22).padding(.leading, 8)
            }
        }
        .frame(height: compact ? 58 : 184)
        .frame(width: compact ? 48 : nil)
        .overlay {
            if let photo {
                GeometryReader { geometry in
                    Image(uiImage: photo).resizable()
                        .aspectRatio(contentMode: isPagePreview ? .fit : .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .background(isPagePreview ? Color(white: 0.94) : .clear).clipped()
                        .overlay(alignment: .bottomLeading) {
                            if !compact && !isPagePreview {
                                Text(notebook.title).font(.title3.bold()).foregroundStyle(.white)
                                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.black.opacity(0.45))
                            }
                        }
                }.clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 16))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct CoverDecoration: View {
    let pattern: CoverPattern
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let w = geometry.size.width, h = geometry.size.height
                switch pattern {
                case .plain: break
                case .diagonal:
                    for i in -2...6 {
                        let x = CGFloat(i) * 55
                        path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x + h, y: h))
                    }
                case .grid:
                    for x in stride(from: CGFloat(0), through: w, by: 24) { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: h)) }
                    for y in stride(from: CGFloat(0), through: h, by: 24) { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: w, y: y)) }
                case .dots:
                    for x in stride(from: CGFloat(12), through: w, by: 22) {
                        for y in stride(from: CGFloat(12), through: h, by: 22) { path.addEllipse(in: CGRect(x: x, y: y, width: 2, height: 2)) }
                    }
                }
            }.stroke(.white.opacity(pattern == .diagonal ? 0.12 : 0.09), lineWidth: pattern == .diagonal ? 18 : 1)
        }.allowsHitTesting(false)
    }
}
