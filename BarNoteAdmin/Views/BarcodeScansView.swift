import SwiftUI

/// 바코드 스캔 현황: 스캔 성공 기록 목록 + 바코드 보기 + 제품 상세
/// (어드민 웹 barcode-scans 페이지 미러링)
struct BarcodeScansView: View {
    @State private var rows: [BarcodeSuccessRow] = []
    @State private var isLoading = false
    @State private var viewingBarcode: BarcodeSheetItem?
    @State private var viewingProduct: BarcodeSheetItem?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if !rows.isEmpty {
                Section {
                    ForEach(rows) { row in
                        BarcodeScanRowView(
                            row: row,
                            onViewBarcode: { viewingBarcode = BarcodeSheetItem(value: row.barcodeId) },
                            onViewProduct: { viewingProduct = BarcodeSheetItem(value: row.barcodeId) }
                        )
                    }
                } header: {
                    Text("바코드 스캔에 성공한 기록 · 총 \(rows.count)건")
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
                    "스캔 기록이 없습니다",
                    systemImage: "barcode.viewfinder",
                    description: Text("바코드 스캔 성공 기록이 없습니다.")
                )
                .listRowSeparator(.hidden)
            }
        }
        .navigationTitle("바코드 스캔 현황")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task {
            if rows.isEmpty {
                isLoading = true
                await load()
                isLoading = false
            }
        }
        // 바코드 보기
        .sheet(item: $viewingBarcode) { item in
            NavigationStack {
                BarcodeSymbolView(value: item.value)
                    .padding(24)
                    .navigationTitle("바코드 보기")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
        // 제품 상세
        .sheet(item: $viewingProduct) { item in
            BarcodeProductSheet(barcodeId: item.value)
        }
        .errorAlert($errorMessage)
    }

    private func load() async {
        do {
            let successes = try await AdminAPI.getBarcodeSuccesses()
            // updated_at이 "yyyy-MM-dd HH:mm:ss" 형식이라 문자열 비교로 최신순 정렬 가능
            rows = successes
                .map { BarcodeSuccessRow(barcodeId: $0.key, success: $0.value) }
                .sorted { $0.success.updatedAt > $1.success.updatedAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 스캔 현황 행: 바코드 번호 + 스캔 횟수 + 마지막 스캔 일시 + 액션
struct BarcodeScanRowView: View {
    let row: BarcodeSuccessRow
    let onViewBarcode: () -> Void
    let onViewProduct: () -> Void

    /// 스캔 횟수에 따른 색상 (웹과 동일: 10회 이상 초록, 3회 이상 파랑)
    private var successCountColor: Color {
        let count = row.success.successCount
        if count >= 10 { return .green }
        if count >= 3 { return .blue }
        return .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(row.barcodeId)
                    .font(.subheadline.monospaced().weight(.medium))
                    .textSelection(.enabled)
                Spacer()
                TagView(text: "\(row.success.successCount)회", color: successCountColor)
            }

            HStack {
                Text("마지막 스캔: \(row.success.updatedAt)")
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

                Button {
                    onViewProduct()
                } label: {
                    Label("제품 상세", systemImage: "shippingbox")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 바코드로 조회한 제품 상세 시트 (읽기 전용)
struct BarcodeProductSheet: View {
    let barcodeId: String
    @Environment(\.dismiss) private var dismiss

    @State private var info: ProductByBarcodeResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let info {
                    detailList(info)
                } else if isLoading {
                    ProgressView("제품 정보를 불러오는 중...")
                } else {
                    ContentUnavailableView(
                        "제품 정보를 불러올 수 없습니다",
                        systemImage: "shippingbox",
                        description: errorMessage.map { Text($0) }
                    )
                }
            }
            .navigationTitle("제품 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func detailList(_ info: ProductByBarcodeResponse) -> some View {
        List {
            if let imageIds = info.imageIds, !imageIds.isEmpty {
                Section("제품 이미지") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(imageIds, id: \.self) { imageId in
                                RemoteImage(url: C.imageURL(imageId))
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("기본 정보") {
                LabeledContent("제품명") {
                    Text(info.product.name)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("타입") {
                    TagView(text: ProductTypeLabel.label(for: info.product.type), color: .blue)
                }
                LabeledContent("바코드") {
                    Text(barcodeId)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                if let desc = info.product.desc, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let details = info.product.details, hasAnyDetail(details) {
                Section("상세 정보") {
                    if let style = details.style {
                        LabeledContent("스타일", value: ProductStyleLabel.label(for: style))
                    }
                    if let grape = details.grape {
                        LabeledContent("포도 품종", value: GrapeVarietyLabel.label(for: grape))
                    }
                    if let manufacturer = details.manufacturer, !manufacturer.isEmpty {
                        LabeledContent("제조사", value: manufacturer)
                    }
                    if let country = details.country, !country.isEmpty {
                        LabeledContent("국가", value: country)
                    }
                    if let alcohol = details.alcohol {
                        LabeledContent("도수", value: "\(Self.numberText(alcohol))%")
                    }
                    if let ibu = details.ibu {
                        LabeledContent("IBU", value: Self.numberText(ibu))
                    }
                }
            }

            Section("통계") {
                LabeledContent("평점") {
                    RatingLabel(rating: info.product.rating)
                }
                LabeledContent("노트 수", value: "\(info.product.noteCount ?? 0)개")
                LabeledContent("즐겨찾기 수", value: info.favoriteCount.map { "\($0)개" } ?? "-")
                LabeledContent("등록일", value: DateLabel.display(info.product.registered))
            }

            Section {
                LabeledContent("제품 ID") {
                    Text(info.product.id)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private func hasAnyDetail(_ details: ProductDetails) -> Bool {
        details.style != nil
            || details.grape != nil
            || !(details.manufacturer ?? "").isEmpty
            || !(details.country ?? "").isEmpty
            || details.alcohol != nil
            || details.ibu != nil
    }

    /// 12.0 → "12", 12.5 → "12.5"
    private static func numberText(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(value)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            info = try await AdminAPI.getProductByBarcode(barcodeId: barcodeId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
