import Foundation

// MARK: - 공통 응답 envelope

/// 서버 공통 응답 형태: `{ "result": Bool, "data": T?, "error": Int? }`
struct APIEnvelope<T: Decodable>: Decodable {
    let result: Bool?
    let data: T?
    let error: Int?
}

/// 에러 판별 전용 (data 타입과 무관하게 디코딩)
struct APIErrorEnvelope: Decodable {
    let result: Bool?
    let error: Int?
}

// MARK: - 모델 (어드민 웹 src/types/api.ts 미러링)

struct Product: Codable, Hashable, Identifiable {
    let id: String
    var name: String
    var type: Int
    var desc: String?
    var rating: Double?
    var flavorInfos: [String: Int]?
    var details: ProductDetails?
    var registered: String?
    var noteCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, type, desc, rating, details, registered
        case flavorInfos = "flavor_infos"
        case noteCount = "note_count"
    }
}

struct ProductDetails: Codable, Hashable {
    var style: Int?
    var grape: Int?
    var manufacturer: String?
    var country: String?
    var alcohol: Double?
    var ibu: Double?
}

struct ProductInfo: Codable, Hashable, Identifiable {
    var product: Product
    var imageIds: [String]?
    var favoriteCount: Int?

    /// 서버는 최상위 id를 보내지 않는다 — 본가 앱과 동일하게 product.id로 식별
    /// (어드민 웹 types/api.ts의 id 선언은 런타임 검증이 없어 실제 응답과 다름)
    var id: String { product.id }

    enum CodingKeys: String, CodingKey {
        case product
        case imageIds = "image_ids"
        case favoriteCount = "favorite_count"
    }
}

struct Report: Codable, Hashable, Identifiable {
    let id: String
    let productId: String
    let userId: String
    let body: String
    let state: Int?
    var reply: String?
    let type: Int
    let registered: String?

    enum CodingKeys: String, CodingKey {
        case id, body, state, reply, type, registered
        case productId = "product_id"
        case userId = "user_id"
    }

    /// 신고 종류 라벨 (어드민 웹과 동일: 0=제품 신고, 1=기타)
    var typeLabel: String {
        switch type {
        case 0: return "제품 신고"
        case 1: return "기타"
        default: return "기타(\(type))"
        }
    }

    /// 답변 완료 여부
    var isReplied: Bool {
        !(reply ?? "").isEmpty
    }
}

struct DashboardStats: Codable {
    var registeredUserCount: Int?
    var monthlyRegisteredUserCount: Int?
    var productCount: Int?
    var monthlyNoteCount: Int?
    var dailyNoteCount: Int?
    var notReplyReportCount: Int?
    var premiumUserCount: Int?
    var webActiveUsers30d: Int?
    var iosActiveUsers30d: Int?
    var androidActiveUsers30d: Int?
    var geminiRequestSuccessCount: Int?
    var geminiRequestFailureCount: Int?
    var barcodeRequestSuccessCount: Int?
    var barcodeRequestFailureCount: Int?

    enum CodingKeys: String, CodingKey {
        case registeredUserCount = "registered_user_count"
        case monthlyRegisteredUserCount = "monthly_registered_user_count"
        case productCount = "product_count"
        case monthlyNoteCount = "monthly_note_count"
        case dailyNoteCount = "daily_note_count"
        case notReplyReportCount = "not_reply_report_count"
        case premiumUserCount = "premium_user_count"
        case webActiveUsers30d = "web_active_users_30d"
        case iosActiveUsers30d = "ios_active_users_30d"
        case androidActiveUsers30d = "android_active_users_30d"
        case geminiRequestSuccessCount = "gemini_request_success_count"
        case geminiRequestFailureCount = "gemini_request_failure_count"
        case barcodeRequestSuccessCount = "barcode_request_success_count"
        case barcodeRequestFailureCount = "barcode_request_failure_count"
    }
}

struct ProductMainImageResponse: Codable {
    let imageId: String?

    enum CodingKeys: String, CodingKey {
        case imageId = "image_id"
    }
}

/// GET admin/product/details 응답 (자동 기입용)
struct ProductDetailsResponse: Codable {
    let desc: String?
    let details: ProductDetails?
}

struct UpdateProductRequest: Encodable {
    let productId: String
    var name: String?
    var desc: String?
    var type: Int?
    var details: ProductDetails?

    enum CodingKeys: String, CodingKey {
        case name, desc, type, details
        case productId = "product_id"
    }
}

struct Flavor: Codable, Hashable, Identifiable {
    let id: String
    let name: String
}

struct User: Codable, Hashable, Identifiable {
    let id: String
    let nickName: String?
    let intro: String?
    let imageId: String?
    let registered: String?
    let premiumExpireAt: String?

    enum CodingKeys: String, CodingKey {
        case id, intro, registered
        case nickName = "nick_name"
        case imageId = "image_id"
        case premiumExpireAt = "premium_expire_at"
    }

    /// 프리미엄 유저 여부 (premium_expire_at 날짜가 존재하고 현재 시각 이후인 경우)
    var isPremium: Bool {
        guard let date = DateLabel.parseDate(premiumExpireAt) else { return false }
        return date > Date()
    }
}

struct UserDetailResponse: Codable {
    let user: User
    let noteCount: Int?
    let followerCount: Int?

    enum CodingKeys: String, CodingKey {
        case user
        case noteCount = "note_count"
        case followerCount = "follower_count"
    }
}

/// 노트 공개 범위 (서버가 모르는 값을 보내도 디코딩이 깨지지 않도록 폴백 처리)
enum PublicScope: Int, Codable {
    case `private` = 0
    case friendsOnly = 1
    case `public` = 2

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = PublicScope(rawValue: raw) ?? .private
    }

    var label: String {
        switch self {
        case .private: return "비공개"
        case .friendsOnly: return "친구 공개"
        case .public: return "전체 공개"
        }
    }

    var systemImage: String {
        switch self {
        case .private: return "lock.fill"
        case .friendsOnly: return "person.2.fill"
        case .public: return "person.3.fill"
        }
    }
}

struct Note: Codable, Hashable, Identifiable {
    let id: String
    let body: String
    let rating: Double?
    let registered: String?
    let publicScope: PublicScope
    let details: [String: Int]?

    enum CodingKeys: String, CodingKey {
        case id, body, rating, registered, details
        case publicScope = "public_scope"
    }
}

struct NoteInfo: Codable, Hashable, Identifiable {
    let note: Note
    let product: Product
    let imageIds: [String]?
    let productImageId: String?
    let flavors: [Flavor]?
    let user: User?

    /// 서버는 최상위 id를 보내지 않는다 — 본가 앱과 동일하게 note.id로 식별
    var id: String { note.id }

    enum CodingKeys: String, CodingKey {
        case note, product, flavors, user
        case imageIds = "image_ids"
        case productImageId = "product_image_id"
    }
}

/// GET admin/barcode/failures 응답의 값 (서버 fail_barcodes.json 항목)
struct BarcodeFailure: Codable, Hashable {
    let updatedAt: String
    let failCount: Int

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case failCount = "fail_count"
    }
}

/// 실패 바코드 목록 행 (맵 키인 barcodeId를 포함해 평탄화한 형태)
struct BarcodeFailureRow: Hashable, Identifiable {
    let barcodeId: String
    let failure: BarcodeFailure

    var id: String { barcodeId }
}

/// GET admin/barcode/successes 응답의 값 (바코드 스캔 성공 기록)
struct BarcodeSuccess: Codable, Hashable {
    let updatedAt: String
    let successCount: Int

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case successCount = "success_count"
    }
}

/// 바코드 스캔 현황 목록 행 (맵 키인 barcodeId를 포함해 평탄화한 형태)
struct BarcodeSuccessRow: Hashable, Identifiable {
    let barcodeId: String
    let success: BarcodeSuccess

    var id: String { barcodeId }
}

/// GET products/barcode/:barcode_id 응답
struct ProductByBarcodeResponse: Codable {
    let product: Product
    let imageIds: [String]?
    let favoriteCount: Int?

    enum CodingKeys: String, CodingKey {
        case product
        case imageIds = "image_ids"
        case favoriteCount = "favorite_count"
    }
}

// MARK: - 날짜 표시 유틸

enum DateLabel {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterNoFraction = ISO8601DateFormatter()

    /// Postgres timestamptz가 마이크로초(6자리)로 내려오는 경우용 폴백
    /// (ISO8601DateFormatter는 밀리초 3자리만 처리)
    private static let microsecondsFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy. MM. dd. HH:mm"
        return formatter
    }()

    /// 서버 timestamptz 문자열을 Date로 파싱
    static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return isoFormatter.date(from: raw)
            ?? isoFormatterNoFraction.date(from: raw)
            ?? microsecondsFormatter.date(from: raw)
    }

    /// 서버 timestamptz 문자열을 "yyyy. MM. dd. HH:mm" 로 변환. 파싱 실패 시 원본 그대로 반환.
    static func display(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "-" }
        if let parsed = parseDate(raw) {
            return displayFormatter.string(from: parsed)
        }
        return raw
    }
}
