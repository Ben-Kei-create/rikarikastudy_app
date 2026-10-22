import SwiftUI

struct CollectionView: View {
    let model: AppModel
    @State private var stage: Stage = .mountain

    var body: some View {
        let rows = CollectionService.rows(for: stage, questions: model.repository.questions,
                                          unlockedIDs: model.unlockedIDs)
        VStack(spacing: 0) {
            // With only the Earth stage (release 1) there is nothing to switch between.
            if FeatureFlags.availableStages.count > 1 {
                Picker("ステージ", selection: $stage) {
                    ForEach(FeatureFlags.availableStages, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()
            }
            List(rows) { row in
                if let q = row.question {
                    NavigationLink {
                        CollectionDetailView(question: q)
                    } label: { rowLabel(id: q.id, text: q.question) }
                    .listRowBackground(Color.clear)
                } else {
                    rowLabel(id: String(row.id.prefix(5)), text: "????").foregroundStyle(Theme.ink.opacity(0.45)).listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.parchment.ignoresSafeArea())
        .navigationTitle("コレクション")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
    }

    private func rowLabel(id: String, text: String) -> some View {
        HStack(spacing: 12) {
            Text(id).font(.system(.footnote, design: .monospaced))
            Text(text).font(.footnote).lineLimit(1).truncationMode(.tail)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}

struct CollectionDetailView: View {
    let question: Question

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("No.\(question.id)").font(.system(.subheadline, design: .monospaced))
                Text(question.question).font(.title3.weight(.bold))
                Divider()
                section("正解", question.correctText)
                if !question.explanation.isEmpty { section("解説", question.explanation) }
            }
            .foregroundStyle(Theme.ink)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.parchment.ignoresSafeArea())
        .navigationTitle("問題詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text(body).font(.body)
        }
    }
}
