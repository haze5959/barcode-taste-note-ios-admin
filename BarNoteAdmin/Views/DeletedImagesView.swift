import SwiftUI

/// 미참조 이미지: 격자 그리드 + 전체 화면 뷰어 + Delete All
/// (어드민 웹 deleted-images 페이지 미러링)
struct DeletedImagesView: View {
    @State private var imageIds: [String] = []
    @State private var isLoading = false
    @State private var isDeleting = false
    @State private var showDeleteAllConfirm = false
    @State private var viewer: ImageViewerState?
    @State private var errorMessage: String?
    @State private var toastMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
    ]

    var body: some View {
        ScrollView {
            if imageIds.isEmpty {
                if isLoading {
                    ProgressView("불러오는 중...")
                        .padding(.top, 120)
                } else {
                    ContentUnavailableView(
                        "미참조 이미지가 없습니다",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("정리할 이미지가 없습니다.")
                    )
                    .padding(.top, 80)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("총 \(imageIds.count)개 (이미지를 탭하면 크게 볼 수 있습니다)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)

                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(Array(imageIds.enumerated()), id: \.element) { index, imageId in
                            RemoteImage(url: C.deletedImageURL(imageId))
                                .aspectRatio(1, contentMode: .fill)
                                .clipped()
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewer = ImageViewerState(index: index)
                                }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("미참조 이미지")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteAllConfirm = true
                } label: {
                    if isDeleting {
                        ProgressView()
                    } else {
                        Text("Delete All")
                            .fontWeight(.semibold)
                            .foregroundStyle(imageIds.isEmpty ? Color.secondary : Color.red)
                    }
                }
                .disabled(imageIds.isEmpty || isDeleting)
            }
        }
        .confirmationDialog(
            "모든 미참조 이미지(\(imageIds.count)개)를 삭제합니다.\n되돌릴 수 없습니다.",
            isPresented: $showDeleteAllConfirm,
            titleVisibility: .visible
        ) {
            Button("전체 삭제", role: .destructive) {
                Task { await deleteAll() }
            }
            Button("취소", role: .cancel) {}
        }
        .fullScreenCover(item: $viewer) { state in
            ImagePagerView(
                urls: imageIds.map { C.deletedImageURL($0) },
                currentIndex: state.index
            )
        }
        .refreshable { await load() }
        .task {
            if imageIds.isEmpty {
                isLoading = true
                await load()
                isLoading = false
            }
        }
        .errorAlert($errorMessage)
        .toast($toastMessage)
    }

    private func load() async {
        do {
            imageIds = try await AdminAPI.getDeletedImages()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 전체 삭제 후 다시 조회해서 갱신 (웹과 동일한 흐름)
    private func deleteAll() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await AdminAPI.deleteDeletedImages()
            toastMessage = "미참조 이미지가 모두 삭제되었습니다."
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
