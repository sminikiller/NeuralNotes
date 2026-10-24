import SwiftUI
import NeuralNotesCore

@MainActor
struct QuickGuidePanel: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarding.completed") private var completed = false
    @AppStorage("guide.completed.v1") private var stored = "[]"
    @State private var query = ""
    private var read: Set<String> { FeatureGuide.completedIDs(stored) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Uno spazio per pensare", systemImage: "book.pages.fill").font(.title2.bold()).foregroundStyle(Brand.accent)
                        Text("Cerca una funzione e segui i passaggi. I progressi restano su questo dispositivo.").foregroundStyle(.secondary)
                        ProgressView(value: Double(read.count), total: Double(FeatureGuide.catalog.count))
                        Text("\(read.count) di \(FeatureGuide.catalog.count) tutorial completati").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                ForEach(GuideCategory.allCases, id: \.self) { category in
                    let guides = FeatureGuide.catalog.filter { $0.category == category && $0.matches(query) }
                    if !guides.isEmpty {
                        Section(category.rawValue) {
                            ForEach(guides) { guide in
                                NavigationLink {
                                    FeatureGuideDetail(guide: guide, stored: $stored)
                                } label: { guideLabel(guide) }
                                .accessibilityIdentifier("guide-\(guide.id)")
                            }
                        }
                    }
                }
                if !FeatureGuide.catalog.contains(where: { $0.matches(query) }) { ContentUnavailableView.search(text: query) }
                if query.isEmpty {
                    Section {
                        Button("Inizia a scrivere", systemImage: "arrow.right") { completed = true; dismiss() }
                        if !read.isEmpty { Button("Azzera progressi della guida", role: .destructive) { stored = "[]" } }
                    }
                }
            }.searchable(text: $query, prompt: "Cerca una funzione o un gesto")
                .navigationTitle("Guida rapida").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { completed = true; dismiss() } } }
        }
    }
    private func guideLabel(_ guide: FeatureGuide) -> some View {
        HStack(spacing: 14) {
            Image(systemName: guide.icon).frame(width: 26).foregroundStyle(Brand.accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(guide.title).font(.headline)
                Text(guide.summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if read.contains(guide.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.accent).accessibilityLabel("Completato") }
        }.padding(.vertical, 4)
    }
}

@MainActor
private struct FeatureGuideDetail: View {
    let guide: FeatureGuide
    @Binding var stored: String
    @State private var step = 0
    private var done: Bool { FeatureGuide.completedIDs(stored).contains(guide.id) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label(guide.category.rawValue, systemImage: guide.icon).font(.headline).foregroundStyle(Brand.accent)
                Text(guide.title).font(.largeTitle.bold())
                Text(guide.summary).font(.title3).foregroundStyle(.secondary)
                ProgressView(value: Double(step + 1), total: Double(guide.steps.count))
                VStack(alignment: .leading, spacing: 16) {
                    Text("Passaggio \(step + 1) di \(guide.steps.count)").font(.caption.bold()).foregroundStyle(Brand.accent)
                    Text(guide.steps[step]).font(.title3).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("guideStep")
                }.padding(24).frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
                    .background(Brand.surface, in: RoundedRectangle(cornerRadius: 22))
                HStack {
                    Button("Indietro", systemImage: "chevron.left") { step -= 1 }.disabled(step == 0)
                    Spacer()
                    if step + 1 < guide.steps.count {
                        Button("Avanti", systemImage: "chevron.right") { step += 1 }.buttonStyle(.borderedProminent)
                    } else {
                        Button(done ? "Completato" : "Segna come completato", systemImage: "checkmark") {
                            var ids = FeatureGuide.completedIDs(stored); ids.insert(guide.id); stored = FeatureGuide.store(ids)
                        }.buttonStyle(.borderedProminent).disabled(done).accessibilityIdentifier("guideComplete")
                    }
                }
                DisclosureGroup("Mostra tutti i passaggi") {
                    ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, text in
                        Text("\(index + 1). \(text)").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                    }
                }
            }.padding(28).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
        }.navigationTitle("Tutorial").navigationBarTitleDisplayMode(.inline)
    }
}
