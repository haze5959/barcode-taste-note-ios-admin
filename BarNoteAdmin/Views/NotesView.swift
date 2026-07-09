import SwiftUI

/// 신규 노트 목록 (읽기 전용) — 어드민 웹 NotesList 미러링
struct NotesView: View {
    @State private var notes: [NoteInfo] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedNote: NoteInfo?
    /// reload가 시작될 때마다 증가 — 이전 요청의 늦은 응답(stale)을 폐기하기 위한 세대 토큰
    @State private var loadGeneration = 0

    var body: some View {
        List {
            ForEach(notes) { info in
                Button {
                    selectedNote = info
                } label: {
                    NoteRow(info: info)
                }
                .foregroundStyle(.primary)
                .onAppear {
                    if info.id == notes.last?.id {
                        Task { await loadNextPage() }
                    }
                }
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }

            if !isLoading && notes.isEmpty {
                ContentUnavailableView(
                    "노트가 없습니다",
                    systemImage: "note.text",
                    description: Text("등록된 노트가 없습니다.")
                )
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle("📝 신규 노트")
        .refreshable { await reload() }
        .task {
            if notes.isEmpty {
                await reload()
            }
        }
        .sheet(item: $selectedNote) { info in
            NoteDetailSheet(info: info)
        }
        .errorAlert($errorMessage)
    }

    private func reload() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer {
            // 내가 최신 세대일 때만 로딩 해제 (더 새로운 reload가 시작됐으면 그쪽이 관리)
            if generation == loadGeneration { isLoading = false }
        }
        do {
            let result = try await AdminAPI.fetchNotes(page: 1)
            guard generation == loadGeneration else { return }
            notes = result
            page = 1
            hasMore = result.count == C.pagingCount
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func loadNextPage() async {
        guard hasMore, !isLoading else { return }
        let generation = loadGeneration
        isLoading = true
        defer {
            if generation == loadGeneration { isLoading = false }
        }
        do {
            let result = try await AdminAPI.fetchNotes(page: page + 1)
            // 대기 중 reload가 시작됐으면 이 응답은 이전 목록 기준이므로 통째로 폐기
            guard generation == loadGeneration else { return }
            let existingIds = Set(notes.map(\.id))
            notes.append(contentsOf: result.filter { !existingIds.contains($0.id) })
            page += 1
            hasMore = result.count == C.pagingCount
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }
}

/// 노트 목록 행
struct NoteRow: View {
    let info: NoteInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(info.note.body.isEmpty ? "(내용 없음)" : info.note.body)
                .font(.subheadline)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(info.product.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                RatingLabel(rating: info.note.rating)
                Image(systemName: info.note.publicScope.systemImage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(info.user?.nickName ?? "알 수 없음")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(DateLabel.display(info.note.registered))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 노트 상세 시트 (읽기 전용)
struct NoteDetailSheet: View {
    let info: NoteInfo
    @Environment(\.dismiss) private var dismiss

    /// 표시할 이미지: 노트 이미지가 없으면 제품 대표 이미지로 대체 (웹과 동일)
    private var displayImageIds: [String] {
        if let ids = info.imageIds, !ids.isEmpty { return ids }
        if let productImageId = info.productImageId { return [productImageId] }
        return []
    }

    var body: some View {
        NavigationStack {
            List {
                if !displayImageIds.isEmpty {
                    Section("참조 이미지") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(displayImageIds, id: \.self) { imageId in
                                    RemoteImage(url: C.imageURL(imageId))
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("노트") {
                    Text(info.note.body.isEmpty ? "(내용 없음)" : info.note.body)
                        .font(.subheadline)

                    LabeledContent("별점") {
                        RatingLabel(rating: info.note.rating)
                    }
                    LabeledContent("공개 범위") {
                        TagView(text: info.note.publicScope.label, color: .blue)
                    }
                    LabeledContent("작성일시", value: DateLabel.display(info.note.registered))
                }

                if let flavors = info.flavors, !flavors.isEmpty {
                    Section("플레이버") {
                        FlowTagList(texts: flavors.map(\.name))
                    }
                }

                if let details = info.note.details, !details.isEmpty {
                    Section("세부 평가") {
                        ForEach(details.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            LabeledContent(key, value: "\(value)")
                        }
                    }
                }

                Section("작성자 / 제품") {
                    LabeledContent("작성자", value: info.user?.nickName ?? "알 수 없음")
                    LabeledContent("제품명", value: info.product.name)
                    LabeledContent("노트 ID") {
                        Text(info.note.id)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .navigationTitle("노트 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}

/// 간단한 태그 나열 뷰
struct FlowTagList: View {
    let texts: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(texts, id: \.self) { text in
                    TagView(text: text, color: .cyan)
                }
            }
        }
    }
}
