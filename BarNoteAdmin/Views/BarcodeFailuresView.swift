import SwiftUI

/// 실패 바코드: 조회 실패 기록 목록 + 개별 삭제 + 바코드 보기
/// (어드민 웹 barcode-failures 페이지 미러링)
struct BarcodeFailuresView: View {
    @State private var rows: [BarcodeFailureRow] = []
    @State private var isLoading = false
    @State private var deletingIds: Set<String> = []
    @State private var viewingBarcode: BarcodeSheetItem?
    @State private var errorMessage: String?
    @State private var toastMessage: String?

    var body: some View {
        List {
            if !rows.isEmpty {
                Section {
                    ForEach(rows) { row in
                        BarcodeFailureRowView(
                            row: row,
                            isDeleting: deletingIds.contains(row.barcodeId),
                            onViewBarcode: { viewingBarcode = BarcodeSheetItem(value: row.barcodeId) },
                            onDelete: { Task { await delete(row.barcodeId) } }
                        )
                    }
                } header: {
                    Text("바코드 조회에 실패한 기록 · 총 \(rows.count)건")
                } footer: {
                    Text("행을 밀어서 삭제할 수도 있습니다.")
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

            if !isLoading && rows.isEmpty {
                ContentUnavailableView(
                    "실패한 바코드가 없습니다",
                    systemImage: "barcode.viewfinder",
                    description: Text("조회에 실패한 바코드 기록이 없습니다.")
                )
                .listRowSeparator(.hidden)
            }
        }
        .navigationTitle("실패 바코드")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task {
            if rows.isEmpty {
                isLoading = true
                await load()
                isLoading = false
            }
        }
        .sheet(item: $viewingBarcode) { item in
            NavigationStack {
                BarcodeSymbolView(value: item.value)
                    .padding(24)
                    .navigationTitle("바코드 보기")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
        .errorAlert($errorMessage)
        .toast($toastMessage)
    }

    private func load() async {
        do {
            let failures = try await AdminAPI.getBarcodeFailures()
            // updated_at이 "yyyy-MM-dd HH:mm:ss" 형식이라 문자열 비교로 최신순 정렬 가능
            rows = failures
                .map { BarcodeFailureRow(barcodeId: $0.key, failure: $0.value) }
                .sorted { $0.failure.updatedAt > $1.failure.updatedAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 삭제 성공 시 재조회 없이 해당 행만 로컬에서 제거 (웹과 동일한 정책)
    private func delete(_ barcodeId: String) async {
        deletingIds.insert(barcodeId)
        defer { deletingIds.remove(barcodeId) }
        do {
            try await AdminAPI.deleteBarcodeFailure(barcodeId: barcodeId)
            rows.removeAll { $0.barcodeId == barcodeId }
            toastMessage = "바코드 \"\(barcodeId)\" 실패 기록이 삭제되었습니다."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 실패 바코드 행: 바코드 번호 + 실패 횟수 + 마지막 실패 일시 + 액션
struct BarcodeFailureRowView: View {
    let row: BarcodeFailureRow
    let isDeleting: Bool
    let onViewBarcode: () -> Void
    let onDelete: () -> Void

    /// 실패 횟수에 따른 색상 (웹과 동일: 5회 이상 빨강, 2회 이상 주황)
    private var failCountColor: Color {
        let count = row.failure.failCount
        if count >= 5 { return .red }
        if count >= 2 { return .orange }
        return .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(row.barcodeId)
                    .font(.subheadline.monospaced().weight(.medium))
                    .textSelection(.enabled)
                Spacer()
                TagView(text: "\(row.failure.failCount)회", color: failCountColor)
            }

            HStack {
                Text("마지막 실패: \(row.failure.updatedAt)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onViewBarcode()
                } label: {
                    Label("바코드", systemImage: "barcode")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("삭제", systemImage: "trash")
                            .font(.caption.weight(.medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isDeleting)
            }
        }
        .padding(.vertical, 2)
        .swipeActions {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }
}
