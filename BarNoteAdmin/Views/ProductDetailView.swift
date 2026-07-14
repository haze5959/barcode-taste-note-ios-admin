import SwiftUI
import PhotosUI

/// 제품 상세: 정보 편집 / 자동 기입 / 이미지 관리 / 바코드 관리 / 병합 / 삭제
/// (어드민 웹 ProductList의 상세 모달을 모바일 화면에 맞게 재구성)
struct ProductDetailView: View {
    let onProductChanged: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let productId: String
    @State private var info: ProductInfo

    // MARK: 편집 폼 상태
    @State private var name: String
    @State private var type: Int
    @State private var desc: String
    @State private var style: Int?
    @State private var grape: Int?
    @State private var manufacturer: String
    @State private var country: String
    @State private var alcoholText: String
    @State private var ibuText: String

    // MARK: 이미지 상태
    @State private var mainImageId: String?
    @State private var allImageIds: [String] = []
    /// 이미지 교체 시 증가 — 같은 image_id의 URL을 바꿔 AsyncImage/URLCache의 이전 이미지를 무효화
    @State private var imageVersion = 0
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showImageUrlAlert = false
    @State private var imageUrlInput = ""
    @State private var viewer: ImageViewerState?

    // MARK: 바코드 상태
    @State private var barcodes: [String] = []
    @State private var showAddBarcodeAlert = false
    @State private var barcodeInput = ""
    @State private var viewingBarcode: BarcodeSheetItem?

    // MARK: 병합/삭제 상태
    @State private var mergeTargetId = ""
    @State private var showMergeConfirm = false
    @State private var showDeleteConfirm = false

    // MARK: 진행/피드백 상태
    @State private var isSaving = false
    @State private var isAutoFilling = false
    @State private var isUploadingImage = false
    @State private var errorMessage: String?
    @State private var toastMessage: String?

    init(initialInfo: ProductInfo, onProductChanged: @escaping () -> Void) {
        self.onProductChanged = onProductChanged
        self.productId = initialInfo.id
        _info = State(initialValue: initialInfo)
        _name = State(initialValue: initialInfo.product.name)
        _type = State(initialValue: initialInfo.product.type)
        _desc = State(initialValue: initialInfo.product.desc ?? "")
        _style = State(initialValue: initialInfo.product.details?.style)
        _grape = State(initialValue: initialInfo.product.details?.grape)
        _manufacturer = State(initialValue: initialInfo.product.details?.manufacturer ?? "")
        _country = State(initialValue: initialInfo.product.details?.country ?? "")
        _alcoholText = State(initialValue: initialInfo.product.details?.alcohol.map { Self.numberText($0) } ?? "")
        _ibuText = State(initialValue: initialInfo.product.details?.ibu.map { Self.numberText($0) } ?? "")
    }

    var body: some View {
        Form {
            imagesSection
            basicInfoSection
            detailsSection
            saveSection
            statsSection
            barcodesSection
            mergeSection
            deleteSection
        }
        .navigationTitle("제품 상세")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSubResources() }
        .errorAlert($errorMessage)
        .toast($toastMessage)
        // 사진 선택 → 업로드
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await uploadPickedPhoto(newItem) }
        }
        // 이미지 URL 입력
        .alert("URL로 이미지 변경", isPresented: $showImageUrlAlert) {
            TextField("이미지 URL", text: $imageUrlInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("적용") {
                Task { await applyImageUrl() }
            }
            Button("취소", role: .cancel) { imageUrlInput = "" }
        } message: {
            Text("이미지 URL을 입력하면 대표 이미지로 등록/변경됩니다.")
        }
        // 바코드 추가
        .alert("바코드 추가", isPresented: $showAddBarcodeAlert) {
            TextField("바코드 번호", text: $barcodeInput)
                .keyboardType(.numberPad)
            Button("추가") {
                Task { await addBarcode() }
            }
            Button("취소", role: .cancel) { barcodeInput = "" }
        }
        // 병합 확인
        .confirmationDialog(
            "이 제품을 대상 제품으로 병합합니다.\n현재 제품의 노트/바코드가 대상 제품으로 옮겨집니다.",
            isPresented: $showMergeConfirm,
            titleVisibility: .visible
        ) {
            Button("병합", role: .destructive) {
                Task { await merge() }
            }
            Button("취소", role: .cancel) {}
        }
        // 삭제 확인
        .confirmationDialog(
            "정말 이 제품을 삭제하시겠습니까?\n되돌릴 수 없습니다.",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                Task { await deleteProduct() }
            }
            Button("취소", role: .cancel) {}
        }
        // 이미지 전체 화면 뷰어
        .fullScreenCover(item: $viewer) { state in
            ImagePagerView(urls: allImageIds.map { versionedImageURL($0) }, currentIndex: state.index)
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
    }

    // MARK: - 섹션

    private var imagesSection: some View {
        Section("이미지") {
            HStack {
                Spacer()
                RemoteImage(url: mainImageId.flatMap { versionedImageURL($0) })
                    .frame(width: 180, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Spacer()
            }
            .listRowSeparator(.hidden)

            HStack(spacing: 12) {
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    Label(isUploadingImage ? "업로드 중..." : "사진으로 변경", systemImage: "photo.badge.plus")
                        .font(.subheadline)
                }
                .disabled(isUploadingImage)

                Spacer()

                Button {
                    showImageUrlAlert = true
                } label: {
                    Label("URL로 변경", systemImage: "link")
                        .font(.subheadline)
                }
                .disabled(isUploadingImage)
            }
            .buttonStyle(.borderless)

            if !allImageIds.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(allImageIds.enumerated()), id: \.element) { index, imageId in
                            RemoteImage(url: versionedImageURL(imageId))
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                // fill 모드 이미지는 프레임 밖까지 레이아웃 경계가 넘치는데
                                // clipShape는 그리기만 자르고 히트 영역은 그대로라
                                // 롱프레스가 옆 타일/스크롤뷰 전체를 집어 올린다.
                                // 히트 영역과 컨텍스트 메뉴 미리보기를 타일 모양으로 제한한다.
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 10))
                                .onTapGesture { viewer = ImageViewerState(index: index) }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        Task { await deleteImage(imageId) }
                                    } label: {
                                        Label("이미지 삭제", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var basicInfoSection: some View {
        Section("기본 정보") {
            LabeledContent("고유 ID") {
                Text(productId)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            TextField("제품명", text: $name, axis: .vertical)

            Picker("타입", selection: $type) {
                ForEach(ProductTypeLabel.all, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
                // 목록에 없는 레거시 타입 값 보존
                if !ProductTypeLabel.all.contains(where: { $0.value == type }) {
                    Text("기타(\(type))").tag(type)
                }
            }

            TextField("설명", text: $desc, axis: .vertical)
                .lineLimit(3...8)
        }
    }

    private var detailsSection: some View {
        Section {
            Picker("스타일", selection: $style) {
                Text("선택 안함").tag(Int?.none)
                ForEach(ProductStyleLabel.groups, id: \.label) { group in
                    Section(group.label) {
                        ForEach(group.options, id: \.value) { option in
                            Text(option.label).tag(Int?.some(option.value))
                        }
                    }
                }
            }

            Picker("포도 품종", selection: $grape) {
                Text("선택 안함").tag(Int?.none)
                ForEach(GrapeVarietyLabel.groups, id: \.label) { group in
                    Section(group.label) {
                        ForEach(group.options, id: \.value) { option in
                            Text(option.label).tag(Int?.some(option.value))
                        }
                    }
                }
            }

            LabeledContent("제조사") {
                TextField("제조사", text: $manufacturer)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("국가 코드") {
                TextField("kr, jp, us ...", text: $country)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            LabeledContent("도수 (%)") {
                TextField("0.0", text: $alcoholText)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
            }
            LabeledContent("IBU") {
                TextField("0", text: $ibuText)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
            }
        } header: {
            HStack {
                Text("상세 정보")
                Spacer()
                Button {
                    Task { await autoFill() }
                } label: {
                    if isAutoFilling {
                        ProgressView()
                    } else {
                        Label("자동 기입", systemImage: "wand.and.stars")
                            .font(.caption)
                    }
                }
                .disabled(isAutoFilling)
            }
        }
    }

    private var saveSection: some View {
        Section {
            Button {
                Task { await save() }
            } label: {
                HStack {
                    Spacer()
                    if isSaving {
                        ProgressView()
                    } else {
                        Label("저장", systemImage: "checkmark.circle.fill")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var statsSection: some View {
        Section("통계") {
            LabeledContent("평점") {
                RatingLabel(rating: info.product.rating)
            }
            LabeledContent("노트 수", value: "\(info.product.noteCount ?? 0)개")
            LabeledContent("즐겨찾기 수", value: info.favoriteCount.map { "\($0)개" } ?? "-")
            LabeledContent("등록일", value: DateLabel.display(info.product.registered))
        }
    }

    private var barcodesSection: some View {
        Section {
            if barcodes.isEmpty {
                Text("등록된 바코드가 없습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(barcodes, id: \.self) { barcode in
                Button {
                    viewingBarcode = BarcodeSheetItem(value: barcode)
                } label: {
                    HStack {
                        Text(barcode)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "barcode")
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Task { await deleteBarcode(barcode) }
                    } label: {
                        Label("삭제", systemImage: "trash")
                    }
                }
            }
        } header: {
            HStack {
                Text("바코드")
                Spacer()
                Button {
                    showAddBarcodeAlert = true
                } label: {
                    Label("추가", systemImage: "plus")
                        .font(.caption)
                }
            }
        } footer: {
            barcodes.isEmpty ? nil : Text("바코드를 밀어서 삭제할 수 있습니다.")
        }
    }

    private var mergeSection: some View {
        Section {
            TextField("병합 대상 제품 ID (UUID)", text: $mergeTargetId)
                .font(.caption.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                showMergeConfirm = true
            } label: {
                Label("이 제품을 대상 제품으로 병합", systemImage: "arrow.triangle.merge")
            }
            .disabled(mergeTargetId.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("제품 병합")
        } footer: {
            Text("현재 제품이 대상 제품에 흡수됩니다.")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Label("제품 삭제", systemImage: "trash")
                    Spacer()
                }
            }
        }
    }

    // MARK: - 데이터 로드

    private func loadSubResources() async {
        // 목록 응답의 product는 desc/details가 빠진 축약형이라
        // 웹 다이얼로그와 동일하게 상세 응답(GET products/:id)으로 폼을 다시 채운다
        async let detailTask = try? AdminAPI.getProductDetail(id: productId)
        async let mainImageTask = try? AdminAPI.getMainImage(productId: productId)
        async let imagesTask = try? AdminAPI.getImages(page: 1, per: 30, productId: productId)
        async let barcodesTask = try? AdminAPI.getProductBarcodes(productId: productId)

        let (detail, mainImage, images, barcodeList) = await (detailTask, mainImageTask, imagesTask, barcodesTask)
        if let detail { applyInfo(detail) }
        mainImageId = mainImage?.imageId
        allImageIds = images ?? []
        barcodes = barcodeList ?? []
    }

    /// 서버 상세 응답으로 info와 편집 폼 상태를 동기화 (init의 초기화와 동일한 매핑)
    private func applyInfo(_ latest: ProductInfo) {
        info = latest
        name = latest.product.name
        type = latest.product.type
        desc = latest.product.desc ?? ""
        style = latest.product.details?.style
        grape = latest.product.details?.grape
        manufacturer = latest.product.details?.manufacturer ?? ""
        country = latest.product.details?.country ?? ""
        alcoholText = latest.product.details?.alcohol.map { Self.numberText($0) } ?? ""
        ibuText = latest.product.details?.ibu.map { Self.numberText($0) } ?? ""
    }

    private func reloadInfo() async {
        if let latest = try? await AdminAPI.getProductDetail(id: productId) {
            applyInfo(latest)
        }
    }

    // MARK: - 액션

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            var details = ProductDetails()
            details.style = style
            details.grape = grape
            details.manufacturer = manufacturer.isEmpty ? nil : manufacturer
            details.country = country.isEmpty ? nil : country
            details.alcohol = Double(alcoholText.replacingOccurrences(of: ",", with: "."))
            details.ibu = Double(ibuText)

            let request = UpdateProductRequest(
                productId: productId,
                name: name,
                desc: desc,
                type: type,
                details: details
            )
            _ = try await AdminAPI.updateProduct(request)
            toastMessage = "제품 정보가 수정되었습니다."
            await reloadInfo()
            onProductChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 자동 기입: 제품명으로 상세 정보를 조회해 폼에 채움 (저장 버튼을 눌러야 반영).
    /// only_details=false — 웹의 "전체 자동 기입"과 동일하게 desc까지 응답에 포함시킴
    private func autoFill() async {
        isAutoFilling = true
        defer { isAutoFilling = false }
        do {
            let response = try await AdminAPI.getProductDetails(productName: name, onlyDetails: false)
            if let details = response.details {
                if let value = details.style { style = value }
                if let value = details.grape { grape = value }
                if let value = details.manufacturer { manufacturer = value }
                if let value = details.country { country = value }
                if let value = details.alcohol { alcoholText = Self.numberText(value) }
                if let value = details.ibu { ibuText = Self.numberText(value) }
            }
            if let newDesc = response.desc, !newDesc.isEmpty {
                desc = newDesc
            }
            toastMessage = "자동 기입되었습니다. 저장 버튼을 눌러 반영해주세요."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uploadPickedPhoto(_ item: PhotosPickerItem) async {
        isUploadingImage = true
        defer {
            isUploadingImage = false
            photoPickerItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let jpegData = Self.jpegData(from: data) else {
                errorMessage = "이미지를 불러올 수 없습니다."
                return
            }
            if let mainImageId {
                // 기존 대표 이미지 교체
                try await AdminAPI.updateImage(imageId: mainImageId, imageData: jpegData)
                toastMessage = "이미지가 성공적으로 변경되었습니다."
            } else {
                // 대표 이미지 신규 등록
                try await AdminAPI.uploadImage(imageData: jpegData, productId: productId)
                toastMessage = "이미지가 성공적으로 등록되었습니다."
            }
            imageVersion += 1   // 같은 image_id라도 새 URL로 다시 로드
            await loadSubResources()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyImageUrl() async {
        let url = imageUrlInput.trimmingCharacters(in: .whitespaces)
        imageUrlInput = ""
        guard !url.isEmpty else { return }
        do {
            // 웹과 동일: 대표 이미지가 있으면 image_id로 교체, 없으면 product_id로 등록
            try await AdminAPI.updateImageUrl(
                imageUrl: url,
                imageId: mainImageId,
                productId: mainImageId == nil ? productId : nil
            )
            toastMessage = "이미지가 성공적으로 변경/등록되었습니다."
            imageVersion += 1   // 같은 image_id라도 새 URL로 다시 로드
            await loadSubResources()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteImage(_ imageId: String) async {
        do {
            try await AdminAPI.deleteImage(id: imageId)
            toastMessage = "이미지가 삭제되었습니다."
            await loadSubResources()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addBarcode() async {
        let barcode = barcodeInput.trimmingCharacters(in: .whitespaces)
        barcodeInput = ""
        guard !barcode.isEmpty else { return }
        do {
            try await AdminAPI.addBarcode(barcodeId: barcode, productId: productId)
            toastMessage = "바코드가 추가되었습니다."
            barcodes = (try? await AdminAPI.getProductBarcodes(productId: productId)) ?? barcodes
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteBarcode(_ barcode: String) async {
        do {
            try await AdminAPI.deleteBarcode(barcodeId: barcode)
            barcodes.removeAll { $0 == barcode }
            toastMessage = "바코드 \"\(barcode)\"가 삭제되었습니다."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func merge() async {
        do {
            try await AdminAPI.mergeProduct(
                productId: productId,
                toProductId: mergeTargetId.trimmingCharacters(in: .whitespaces)
            )
            toastMessage = "제품이 성공적으로 병합되었습니다."
            onProductChanged()
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteProduct() async {
        do {
            try await AdminAPI.deleteProduct(productId: productId)
            onProductChanged()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 유틸

    /// 이미지 교체 후 같은 URL 재사용으로 인한 stale 표시를 막는 캐시 버스터 URL.
    /// 교체 전(imageVersion == 0)에는 쿼리 없는 원본 URL을 사용해 일반 캐시를 유지한다.
    private func versionedImageURL(_ id: String) -> URL? {
        guard imageVersion > 0 else { return C.imageURL(id) }
        return URL(string: "\(C.imageBaseURL)/\(id)?v=\(imageVersion)")
    }

    /// 12.0 → "12", 12.5 → "12.5"
    private static func numberText(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(value)
    }

    /// 선택한 사진을 JPEG 데이터로 변환 (긴 변 1280px로 축소해 업로드 용량 절약)
    private static func jpegData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxDimension: CGFloat = 1280
        let longSide = max(image.size.width, image.size.height)
        guard longSide > maxDimension else {
            return image.jpegData(compressionQuality: 0.85)
        }
        let scale = maxDimension / longSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}
