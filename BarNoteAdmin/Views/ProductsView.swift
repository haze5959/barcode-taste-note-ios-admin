import SwiftUI

/// 제품 목록: 검색 + 무한 스크롤 페이징 (어드민 웹 ProductList의 목록부)
struct ProductsView: View {
    @State private var products: [ProductInfo] = []
    @State private var searchText = ""
    @State private var appliedSearch: String? = nil
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// reload가 시작될 때마다 증가 — 이전 요청의 늦은 응답(stale)을 폐기하기 위한 세대 토큰
    @State private var loadGeneration = 0

    var body: some View {
        List {
            ForEach(products) { info in
                NavigationLink(value: info) {
                    ProductRow(info: info)
                }
                .onAppear {
                    // 마지막 행이 보이면 다음 페이지 로드
                    if info.id == products.last?.id {
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

            if !isLoading && products.isEmpty {
                ContentUnavailableView(
                    "제품이 없습니다",
                    systemImage: "shippingbox",
                    description: Text(appliedSearch == nil ? "등록된 제품이 없습니다." : "검색 결과가 없습니다.")
                )
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle("📦 제품")
        .navigationDestination(for: ProductInfo.self) { info in
            ProductDetailView(initialInfo: info) {
                // 삭제/병합 후 목록 갱신
                Task { await reload() }
            }
        }
        .searchable(text: $searchText, prompt: "제품명 검색")
        .onSubmit(of: .search) {
            appliedSearch = searchText.isEmpty ? nil : searchText
            Task { await reload() }
        }
        .onChange(of: searchText) { _, newValue in
            // 검색어를 모두 지우면 전체 목록으로 복귀
            if newValue.isEmpty && appliedSearch != nil {
                appliedSearch = nil
                Task { await reload() }
            }
        }
        .refreshable { await reload() }
        .task {
            if products.isEmpty {
                await reload()
            }
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
            let result = try await AdminAPI.fetchProducts(search: appliedSearch, page: 1)
            guard generation == loadGeneration else { return }
            products = result
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
            let result = try await AdminAPI.fetchProducts(search: appliedSearch, page: page + 1)
            // 대기 중 reload가 시작됐으면 이 응답은 이전 목록 기준이므로 통째로 폐기
            guard generation == loadGeneration else { return }
            let existingIds = Set(products.map(\.id))
            products.append(contentsOf: result.filter { !existingIds.contains($0.id) })
            page += 1
            hasMore = result.count == C.pagingCount
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }
}

/// 제품 목록 행: 썸네일 + 이름 + 타입/평점/노트 수
struct ProductRow: View {
    let info: ProductInfo

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: info.imageIds?.first.flatMap { C.imageURL($0) })
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(info.product.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    if info.product.needsReview {
                        ReviewNeededBadge()
                    }
                }

                HStack(spacing: 8) {
                    TagView(text: ProductTypeLabel.label(for: info.product.type), color: .blue)
                    RatingLabel(rating: info.product.rating)
                    Text("노트 \(info.product.noteCount ?? 0)개")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
