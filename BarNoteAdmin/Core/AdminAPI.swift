import Foundation
import os

// MARK: - 에러

enum AdminAPIError: LocalizedError {
    case unauthorized
    case server(Int)          // 서버 공통 에러 코드 ({ result: false, error: code })
    case status(Int)          // 그 외 HTTP 오류
    case network(Error)
    case decoding(endpoint: String, detail: String)

    /// 어드민 웹 getErrorMessage()와 동일한 한국어 메시지
    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "인증이 만료되었습니다. 다시 로그인해 주세요."
        case .server(let code):
            switch code {
            case 100: return "서버 내부 오류가 발생했습니다. (100)"
            case 101: return "데이터베이스 오류가 발생했습니다. (101)"
            case 102: return "권한 검증에 실패했습니다. (102)"
            case 103: return "중복된 데이터가 이미 존재합니다. (103)"
            case 104: return "인증 서버(JWKS) 통신에 실패했습니다. (104)"
            case 105: return "요청하신 데이터를 찾을 수 없습니다. (105)"
            case 106: return "잘못된 요청 파라미터입니다. (106)"
            case 107: return "허용된 최대 개수를 초과했습니다. (107)"
            case 108: return "이미지 분석에 실패했습니다. (108)"
            default: return "알 수 없는 오류가 발생했습니다. (Error Code: \(code))"
            }
        case .status(let code):
            if code == 404 { return "요청하신 정보를 찾을 수 없습니다. (404)" }
            return "서버 오류가 발생했습니다. (\(code))"
        case .network:
            return "네트워크 오류가 발생했습니다. 서버 상태를 확인해 주세요."
        case .decoding(let endpoint, let detail):
            // 관리자 전용 앱이므로 원인 파악에 필요한 상세를 알럿에도 그대로 노출한다
            return "응답 데이터를 해석할 수 없습니다.\n[\(endpoint)] \(detail)"
        }
    }
}

// MARK: - API 클라이언트

/// 어드민 웹 src/api/admin.ts의 apiFetch/엔드포인트를 그대로 이식한 클라이언트
enum AdminAPI {
    /// API 오류 진단용 로거 (Xcode 콘솔/Console.app에서 subsystem으로 필터링)
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BarNoteAdmin",
        category: "AdminAPI"
    )

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    // MARK: 공통 요청 처리

    private static func request(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        jsonBody: Data? = nil,
        multipart: (boundary: String, body: Data)? = nil
    ) async throws -> Data {
        // 문자열 결합으로 URL 구성: "images/" 처럼 trailing slash가 있는 경로를 그대로 보존하기 위함
        guard var components = URLComponents(string: C.apiBaseURL.absoluteString + "/" + path) else {
            throw AdminAPIError.status(-1)
        }
        if !query.isEmpty {
            components.queryItems = query
            // 웹(URLSearchParams)과 동일하게 '+'를 %2B로 인코딩
            // (URLComponents는 '+'를 그대로 두는데, 서버는 쿼리의 '+'를 공백으로 해석함)
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else {
            throw AdminAPIError.status(-1)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method

        // 토큰을 확보하지 못하면 무인증 요청을 보내지 않고 즉시 실패시킨다
        // (무인증 요청 → 401 → 유효한 크레덴셜까지 삭제되는 연쇄 오동작 방지)
        let token: String
        do {
            token = try await AuthManager.shared.accessToken()
        } catch AuthManager.TokenError.transient {
            throw AdminAPIError.network(URLError(.notConnectedToInternet))
        } catch {
            throw AdminAPIError.unauthorized
        }
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let multipart {
            urlRequest.setValue("multipart/form-data; boundary=\(multipart.boundary)", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = multipart.body
        } else if let jsonBody {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = jsonBody
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            logger.error("네트워크 오류 [\(method, privacy: .public) \(path, privacy: .public)] \(String(describing: error), privacy: .public)")
            throw AdminAPIError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AdminAPIError.status(-1)
        }

        if httpResponse.statusCode == 401 {
            logger.error("401 인증 실패 [\(method, privacy: .public) \(path, privacy: .public)] — 크레덴셜 정리 후 로그인 화면 전환")
            await AuthManager.shared.handleUnauthorized()
            throw AdminAPIError.unauthorized
        }

        // 상태 코드와 무관하게 서버 공통 에러 envelope({ result: false, error: code })를 우선 확인
        if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data),
           envelope.result == false, let code = envelope.error {
            logger.error("서버 에러 코드 \(code) [\(method, privacy: .public) \(path, privacy: .public)] (HTTP \(httpResponse.statusCode))")
            throw AdminAPIError.server(code)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            logger.error("HTTP \(httpResponse.statusCode) [\(method, privacy: .public) \(path, privacy: .public)] 본문: \(bodySnippet(data), privacy: .public)")
            throw AdminAPIError.status(httpResponse.statusCode)
        }

        return data
    }

    /// envelope의 data 필드를 꺼내 디코딩. envelope 형태가 아니면 원본을 그대로 디코딩.
    /// 실패 시 엔드포인트·필드 경로·원인을 로그와 에러 메시지에 남긴다.
    private static func decode<T: Decodable>(_ data: Data, endpoint: String) throws -> T {
        let decoder = JSONDecoder()

        // envelope 우선 시도. 실패해도 바로 버리지 않고 에러를 보관한다 —
        // envelope 응답의 payload 필드 하나가 깨진 경우 실제 원인은 이쪽에 있고,
        // 이어지는 bare 디코딩은 최상위 타입 불일치로만 보고되기 때문.
        let envelopeError: Error?
        do {
            if let payload = try decoder.decode(APIEnvelope<T>.self, from: data).data {
                return payload
            }
            envelopeError = nil   // envelope 형태는 맞지만 data가 비어 있음 — bare 디코딩으로 폴백
        } catch {
            envelopeError = error
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // 두 시도 중 codingPath가 더 깊은 쪽이 실제 원인에 가깝다
            let detail = deeperErrorDescription(bare: error, envelope: envelopeError)
            let message = """
            디코딩 실패 [\(endpoint)] → \(T.self)
            원인: \(detail)
            bare 시도: \(describeDecodingError(error))
            envelope 시도: \(envelopeError.map(describeDecodingError) ?? "성공했으나 data 필드 없음")
            응답 본문: \(bodySnippet(data))
            """
            logger.error("\(message, privacy: .public)")
            throw AdminAPIError.decoding(endpoint: endpoint, detail: detail)
        }
    }

    /// bare/envelope 두 디코딩 에러 중 더 구체적인(codingPath가 깊은) 쪽의 설명을 고른다
    private static func deeperErrorDescription(bare: Error, envelope: Error?) -> String {
        guard let envelope else { return describeDecodingError(bare) }
        return codingDepth(envelope) >= codingDepth(bare)
            ? describeDecodingError(envelope)
            : describeDecodingError(bare)
    }

    private static func codingDepth(_ error: Error) -> Int {
        guard let decodingError = error as? DecodingError else { return -1 }
        switch decodingError {
        case .keyNotFound(_, let context), .typeMismatch(_, let context),
             .valueNotFound(_, let context), .dataCorrupted(let context):
            return context.codingPath.count
        @unknown default:
            return -1
        }
    }

    /// DecodingError를 "어느 필드가 왜" 형태의 한 줄로 요약
    private static func describeDecodingError(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return String(describing: error)
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            return "\(fieldPath(context.codingPath))에 필수 키 '\(key.stringValue)' 없음"
        case .typeMismatch(let type, let context):
            return "\(fieldPath(context.codingPath)) 타입 불일치 — \(type) 예상 (\(context.debugDescription))"
        case .valueNotFound(let type, let context):
            return "\(fieldPath(context.codingPath)) 값이 null — \(type) 예상"
        case .dataCorrupted(let context):
            let underlying = (context.underlyingError as NSError?)?
                .userInfo[NSDebugDescriptionErrorKey] as? String
            return "JSON 형식 오류 — \(underlying ?? context.debugDescription)"
        @unknown default:
            return String(describing: decodingError)
        }
    }

    /// codingPath를 "data.[3].product.rating" 형태의 문자열로 변환
    private static func fieldPath(_ codingPath: [CodingKey]) -> String {
        var result = ""
        for key in codingPath {
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return result.isEmpty ? "(최상위)" : result
    }

    /// 로그용 응답 본문 스니펫 (너무 긴 본문은 잘라낸다)
    private static func bodySnippet(_ data: Data, limit: Int = 800) -> String {
        guard !data.isEmpty else { return "(빈 응답)" }
        let text = String(decoding: data.prefix(limit), as: UTF8.self)
        return data.count > limit ? text + " …(총 \(data.count)바이트)" : text
    }

    private static func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try decode(try await request(path: path, query: query), endpoint: path)
    }

    private static func send<T: Decodable>(_ path: String, method: String, body: some Encodable) async throws -> T {
        let jsonBody = try JSONEncoder().encode(body)
        return try decode(try await request(path: path, method: method, jsonBody: jsonBody), endpoint: path)
    }

    /// 본문 없는 요청 (DELETE 등) — 응답 data는 무시
    private static func sendVoid(_ path: String, method: String) async throws {
        _ = try await request(path: path, method: method)
    }

    /// JSON 본문을 보내는 요청 — 응답 data는 무시
    private static func sendVoid(_ path: String, method: String, body: some Encodable) async throws {
        let jsonBody = try JSONEncoder().encode(body)
        _ = try await request(path: path, method: method, jsonBody: jsonBody)
    }

    /// multipart/form-data 본문 구성 (본가 앱 NetworkClient.upload와 동일한 포맷)
    private static func multipartBody(
        boundary: String,
        fields: [(name: String, value: String)],
        fileFieldName: String,
        fileData: Data,
        mimeType: String = "image/jpeg"
    ) -> Data {
        var body = Data()
        for field in fields {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n".utf8))
            body.append(Data(field.value.utf8))
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"image.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n".utf8))
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    // MARK: - 대시보드

    // GET admin/dashboard
    static func getDashboard() async throws -> DashboardStats {
        try await get("admin/dashboard")
    }

    // MARK: - 신고

    // GET admin/report
    static func getReports() async throws -> [Report] {
        try await get("admin/report")
    }

    // PUT admin/report
    static func updateReport(id: String, reply: String) async throws {
        struct Body: Encodable {
            let id: String
            let reply: String
        }
        try await sendVoid("admin/report", method: "PUT", body: Body(id: id, reply: reply))
    }

    // MARK: - 제품

    // GET /products (검색 + 페이징, page는 1부터)
    static func fetchProducts(search: String?, page: Int) async throws -> [ProductInfo] {
        var query: [URLQueryItem] = [
            .init(name: "page", value: String(page)),
            .init(name: "per", value: String(C.pagingCount)),
            .init(name: "order_by", value: "registered"),
            .init(name: "skip_record", value: String(true)),
        ]
        if let search, !search.isEmpty {
            query.append(.init(name: "name", value: search))
        }
        return try await get("products", query: query)
    }

    // GET /products/:id
    static func getProductDetail(id: String) async throws -> ProductInfo {
        try await get("products/\(id)", query: [.init(name: "skip_record", value: String(true))])
    }

    // GET admin/product/details (자동 기입)
    static func getProductDetails(productName: String, onlyDetails: Bool) async throws -> ProductDetailsResponse {
        try await get("admin/product/details", query: [
            .init(name: "product_name", value: productName),
            .init(name: "only_details", value: onlyDetails ? "true" : "false"),
        ])
    }

    // GET admin/product/main_image
    static func getMainImage(productId: String) async throws -> ProductMainImageResponse {
        try await get("admin/product/main_image", query: [
            .init(name: "product_id", value: productId),
        ])
    }

    // PUT admin/product
    static func updateProduct(_ requestBody: UpdateProductRequest) async throws -> Product {
        try await send("admin/product", method: "PUT", body: requestBody)
    }

    // POST admin/product/merge
    static func mergeProduct(productId: String, toProductId: String) async throws {
        struct Body: Encodable {
            let productId: String
            let toProductId: String

            enum CodingKeys: String, CodingKey {
                case productId = "product_id"
                case toProductId = "to_product_id"
            }
        }
        try await sendVoid("admin/product/merge", method: "POST", body: Body(productId: productId, toProductId: toProductId))
    }

    // DELETE admin/products/:product_id
    static func deleteProduct(productId: String) async throws {
        try await sendVoid("admin/products/\(productId)", method: "DELETE")
    }

    // GET admin/product/barcodes
    static func getProductBarcodes(productId: String) async throws -> [String] {
        try await get("admin/product/barcodes", query: [
            .init(name: "product_id", value: productId),
        ])
    }

    // MARK: - 바코드

    private struct BarcodeBody: Encodable {
        let barcodeId: String
        let productId: String

        enum CodingKeys: String, CodingKey {
            case barcodeId = "barcode_id"
            case productId = "product_id"
        }
    }

    // POST admin/barcode - 새 바코드 추가
    static func addBarcode(barcodeId: String, productId: String) async throws {
        try await sendVoid("admin/barcode", method: "POST", body: BarcodeBody(barcodeId: barcodeId, productId: productId))
    }

    // PUT admin/barcode - 바코드의 product_id 수정
    static func updateBarcode(barcodeId: String, productId: String) async throws {
        try await sendVoid("admin/barcode", method: "PUT", body: BarcodeBody(barcodeId: barcodeId, productId: productId))
    }

    // DELETE admin/barcode/:barcode_id
    static func deleteBarcode(barcodeId: String) async throws {
        try await sendVoid("admin/barcode/\(barcodeId)", method: "DELETE")
    }

    // MARK: - 노트

    // GET admin/notes
    static func fetchNotes(page: Int, per: Int = C.pagingCount) async throws -> [NoteInfo] {
        try await get("admin/notes", query: [
            .init(name: "page", value: String(page)),
            .init(name: "per", value: String(per)),
        ])
    }

    // MARK: - 유저

    // GET /users/:id
    static func getUserDetail(id: String) async throws -> UserDetailResponse {
        try await get("users/\(id)")
    }

    // MARK: - 이미지

    // GET /images
    static func getImages(page: Int, per: Int, productId: String? = nil, noteId: String? = nil) async throws -> [String] {
        var query: [URLQueryItem] = [
            .init(name: "page", value: String(page)),
            .init(name: "per", value: String(per)),
        ]
        if let productId { query.append(.init(name: "product_id", value: productId)) }
        if let noteId { query.append(.init(name: "note_id", value: noteId)) }
        return try await get("images", query: query)
    }

    // POST admin/image - 기존 이미지 교체 (multipart)
    static func updateImage(imageId: String, imageData: Data) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = multipartBody(
            boundary: boundary,
            fields: [("image_id", imageId)],
            fileFieldName: "image",
            fileData: imageData
        )
        _ = try await request(path: "admin/image", method: "POST", multipart: (boundary, body))
    }

    // POST admin/image/url - URL로 이미지 등록/교체
    static func updateImageUrl(imageUrl: String, imageId: String? = nil, productId: String? = nil) async throws {
        struct Body: Encodable {
            let addImageUrl: String
            let imageId: String?
            let productId: String?

            enum CodingKeys: String, CodingKey {
                case addImageUrl = "add_image_url"
                case imageId = "image_id"
                case productId = "product_id"
            }
        }
        try await sendVoid("admin/image/url", method: "POST", body: Body(addImageUrl: imageUrl, imageId: imageId, productId: productId))
    }

    // POST /images/ - 새 이미지 업로드
    static func uploadImage(imageData: Data, productId: String? = nil, noteId: String? = nil) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"
        var fields: [(String, String)] = [("id", UUID().uuidString)]
        if let productId { fields.append(("product_id", productId)) }
        if let noteId { fields.append(("note_id", noteId)) }
        let body = multipartBody(
            boundary: boundary,
            fields: fields,
            fileFieldName: "image",
            fileData: imageData
        )
        _ = try await request(path: "images/", method: "POST", multipart: (boundary, body))
    }

    // DELETE admin/images/:id
    static func deleteImage(id: String) async throws {
        try await sendVoid("admin/images/\(id)", method: "DELETE")
    }

    // MARK: - 미참조 이미지

    // GET admin/deleted/images - 삭제된 이미지 ID(image_id) 목록 조회
    static func getDeletedImages() async throws -> [String] {
        try await get("admin/deleted/images")
    }

    // DELETE admin/deleted/images - 삭제된 이미지 일괄 정리
    static func deleteDeletedImages() async throws {
        try await sendVoid("admin/deleted/images", method: "DELETE")
    }

    // MARK: - 실패 바코드

    // GET admin/barcode/failures - 바코드 조회 실패 목록(fail_barcodes.json)
    static func getBarcodeFailures() async throws -> [String: BarcodeFailure] {
        try await get("admin/barcode/failures")
    }

    // DELETE admin/barcode/failures/:barcode_id - 실패 목록에서 해당 바코드 항목 삭제
    static func deleteBarcodeFailure(barcodeId: String) async throws {
        try await sendVoid("admin/barcode/failures/\(barcodeId)", method: "DELETE")
    }

    // MARK: - 바코드 스캔 현황

    // GET admin/barcode/successes - 바코드 스캔 성공 목록
    static func getBarcodeSuccesses() async throws -> [String: BarcodeSuccess] {
        try await get("admin/barcode/successes")
    }

    // GET products/barcode/:barcode_id - 바코드로 제품 조회
    static func getProductByBarcode(barcodeId: String) async throws -> ProductByBarcodeResponse {
        try await get("products/barcode/\(barcodeId)?skip_record=true")
    }
}
