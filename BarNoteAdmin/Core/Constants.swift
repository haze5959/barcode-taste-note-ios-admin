import Foundation

/// 앱 전역 상수
enum C {
    /// API 서버 주소 (어드민 웹의 API_BASE_URL 프로덕션 값과 동일)
    static let apiBaseURL = URL(string: "https://api.barnote.net")!
    /// 이미지 원본 주소 (어드민 웹의 `/images/{id}` 상대 경로가 프로덕션에서 해석되는 주소)
    static let imageBaseURL = "https://barnote.net/images"
    /// 미참조(삭제 대상) 이미지 원본 주소
    static let deletedImageBaseURL = "https://barnote.net/deleted/images"
    /// Auth0 audience — 본가 앱(iOSBarcodeTasteNote)과 동일
    static let authAudience = "https://barnote.net/"
    /// 본가 앱(BarNote)의 번들 ID.
    /// Auth0 테넌트의 Allowed Callback URLs에 이미 등록된 본가 앱 콜백 URL을
    /// 재사용하기 위해 필요 (어드민 앱 전용 콜백을 대시보드에 추가하지 않아도 됨)
    static let mainAppBundleId = "com.oq.barnote"
    /// 목록 페이지당 항목 수 (어드민 웹과 동일)
    static let pagingCount = 20

    static func imageURL(_ id: String) -> URL? {
        URL(string: "\(imageBaseURL)/\(id)")
    }

    static func deletedImageURL(_ id: String) -> URL? {
        URL(string: "\(deletedImageBaseURL)/\(id)")
    }
}

/// 제품 타입 (서버 Int 코드). 본가 앱과 동일한 정의.
enum ProductTypeLabel {
    static let all: [(value: Int, label: String)] = [
        (0, "🍷 와인"),
        (1, "🥃 위스키"),
        (2, "🍺 맥주"),
        (3, "🍶 소주/사케"),
        (4, "🍸 리큐르/스피릿"),
        (7, "🥤 기타"),
    ]

    static func label(for value: Int) -> String {
        all.first(where: { $0.value == value })?.label ?? "기타(\(value))"
    }
}

/// 제품 스타일 코드 ↔ 라벨 (어드민 웹 PRODUCT_STYLE_GROUPS 미러링)
enum ProductStyleLabel {
    static let groups: [(label: String, options: [(value: Int, label: String)])] = [
        ("와인", [
            (0, "레드 와인"), (1, "화이트 와인"), (2, "로제 와인"), (3, "스파클링 와인"),
            (4, "디저트 와인"), (5, "주정강화 와인"), (6, "내추럴 와인"),
        ]),
        ("위스키", [
            (100, "싱글 몰트 스카치"), (101, "블렌디드 스카치"), (102, "싱글 그레인 스카치"),
            (103, "버번"), (104, "라이 위스키"), (105, "테네시 위스키"), (106, "아이리시 위스키"),
            (107, "재패니즈 위스키"), (108, "캐네디언 위스키"), (109, "기타 월드 위스키"),
        ]),
        ("맥주", [
            (200, "라거"), (201, "필스너"), (202, "페일 에일"), (203, "IPA"), (204, "헤이지 IPA"),
            (205, "스타우트"), (206, "포터"), (207, "밀맥주"), (208, "사워 비어"),
            (209, "벨지안 에일"), (210, "앰버 에일"),
        ]),
        ("소주/사케", [
            (300, "소주"), (301, "과일 소주"), (302, "준마이"), (303, "준마이 긴조"),
            (304, "준마이 다이긴조"), (305, "긴조"), (306, "다이긴조"), (307, "혼조조"),
            (308, "니고리"), (309, "청주"), (310, "약주"), (311, "막걸리"),
        ]),
        ("리큐르/스피릿", [
            (400, "보드카"), (401, "진"), (402, "라이트 럼"), (403, "다크 럼"),
            (404, "스파이스드 럼"), (405, "데킬라"), (406, "메즈칼"), (407, "브랜디"),
            (408, "꼬냑"), (409, "아르마냑"), (410, "압생트"), (411, "백주"), (412, "리큐르"),
        ]),
        ("칵테일", [
            (500, "클래식 칵테일"), (501, "크래프트 칵테일"), (502, "티키 칵테일"),
            (503, "사워 칵테일"), (504, "하이볼"), (505, "프로즌 칵테일"), (506, "목테일"),
        ]),
        ("커피", [
            (600, "에스프레소"), (601, "아메리카노"), (602, "라떼"), (603, "카푸치노"),
            (604, "마키아토"), (605, "플랫 화이트"), (606, "모카"), (607, "드립 커피"),
            (608, "푸어 오버"), (609, "콜드 브루"), (610, "싱글 오리진"),
        ]),
        ("기타", [
            (700, "기타"),
        ]),
    ]

    static let labels: [Int: String] = {
        var map: [Int: String] = [:]
        for group in groups {
            for option in group.options {
                map[option.value] = option.label
            }
        }
        return map
    }()

    static func label(for value: Int) -> String {
        labels[value] ?? "알 수 없음(\(value))"
    }
}

/// 포도 품종 코드 ↔ 라벨 (어드민 웹 GRAPE_VARIETY_GROUPS 미러링)
enum GrapeVarietyLabel {
    static let groups: [(label: String, options: [(value: Int, label: String)])] = [
        ("레드", [
            (0, "까베르네 쇼비뇽"), (1, "메를로"), (2, "피노 누아"), (3, "시라"), (4, "말벡"),
            (5, "산지오베제"), (6, "템프라니요"), (7, "네비올로"), (8, "그르나슈"), (9, "진판델"),
            (10, "까베르네 프랑"), (11, "까르미네르"), (12, "가메"), (13, "몬테풀치아노"), (14, "쁘띠 베르도"),
        ]),
        ("화이트", [
            (100, "샤르도네"), (101, "쇼비뇽 블랑"), (102, "리슬링"), (103, "피노 그리지오"),
            (104, "게뷔르츠트라미너"), (105, "슈냉 블랑"), (106, "비오니에"), (107, "세미용"),
            (108, "모스카토"), (109, "알바리뇨"), (110, "피노 블랑"),
        ]),
        ("블렌드/기타", [
            (200, "레드 블렌드"), (201, "화이트 블렌드"), (299, "기타"),
        ]),
    ]

    static let labels: [Int: String] = {
        var map: [Int: String] = [:]
        for group in groups {
            for option in group.options {
                map[option.value] = option.label
            }
        }
        return map
    }()

    static func label(for value: Int) -> String {
        labels[value] ?? "알 수 없음(\(value))"
    }
}
