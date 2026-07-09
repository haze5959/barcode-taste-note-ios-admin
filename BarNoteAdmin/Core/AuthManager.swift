import Foundation
import Observation
import Auth0

/// Auth0 인증 상태 관리 (본가 앱 iOSBarcodeTasteNote의 AuthStore 방식을 단순화해 이식)
@MainActor
@Observable
final class AuthManager {
    static let shared = AuthManager()

    enum State {
        case checking   // 앱 시작 직후 저장된 크레덴셜 확인 중
        case loggedOut
        case loggedIn
    }

    private(set) var state: State = .checking
    /// 로그인 실패 메시지 (LoginView에서 알럿으로 표시)
    var loginErrorMessage: String?

    private let credentialsManager = CredentialsManager(authentication: Auth0.authentication())

    /// 본가 앱(com.oq.barnote)의 Auth0 콜백 URL.
    /// Auth0 대시보드의 Allowed Callback URLs에 이미 등록되어 있는 값을 재사용하므로
    /// 어드민 앱을 위한 테넌트 설정 변경이 필요 없다.
    /// (로그인 웹뷰는 ASWebAuthenticationSession이라 콜백이 다른 앱으로 새지 않음)
    private static let callbackURL: URL = {
        guard let url = Bundle.main.url(forResource: "Auth0", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any],
              let domain = dict["Domain"] as? String,
              let callback = URL(string: "\(C.mainAppBundleId)://\(domain)/ios/\(C.mainAppBundleId)/callback") else {
            fatalError("Auth0.plist에서 Domain을 읽을 수 없습니다")
        }
        return callback
    }()

    private init() {}

    /// 토큰 확보 실패 원인 구분
    enum TokenError: Error {
        case transient        // 네트워크 등 일시적 문제 — 세션은 유지, 해당 요청만 실패
        case sessionInvalid   // 리프레시 토큰 무효 — 재로그인 필요
    }

    /// 네트워크성(일시적) 에러 판별 — 본가 앱 AuthStore와 동일한 정책.
    /// 일시적 갱신 실패를 세션 무효로 오판해 크레덴셜을 지우지 않기 위함.
    private static func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return true }
        let description = String(describing: error).lowercased()
        return description.contains("network")
            || description.contains("connection")
            || description.contains("timeout")
            || description.contains("offline")
    }

    /// 앱 시작 시 저장된 크레덴셜로 로그인 상태 복원
    func bootstrap() async {
        guard credentialsManager.hasValid(minTTL: 60) || credentialsManager.canRenew() else {
            state = .loggedOut
            return
        }
        do {
            _ = try await credentialsManager.credentials(minTTL: 60)
            state = .loggedIn
        } catch {
            if Self.isNetworkError(error) {
                // 오프라인 콜드 스타트 — 세션은 유효할 수 있으므로 로그인 화면으로 떨어뜨리지 않고
                // 메인 화면으로 진입시킨다. 이후 API 호출 시점에 네트워크 오류로 표면화되고,
                // 네트워크가 복구되면 다음 호출에서 자동 갱신된다.
                state = .loggedIn
            } else {
                _ = credentialsManager.clear()
                state = .loggedOut
            }
        }
    }

    /// Google 로그인 (어드민 웹과 동일하게 Google 커넥션만 사용)
    func login() async {
        loginErrorMessage = nil
        do {
            let credentials = try await Auth0
                .webAuth()
                .audience(C.authAudience)
                .scope("openid profile offline_access")
                .connection("google-oauth2")
                .redirectURL(Self.callbackURL)
                .start()
            _ = credentialsManager.store(credentials: credentials)
            state = .loggedIn
        } catch let error as WebAuthError where error == .userCancelled {
            // 사용자가 로그인 창을 닫음 — 무시
        } catch {
            loginErrorMessage = "로그인에 실패했습니다: \(error.localizedDescription)"
        }
    }

    /// 로컬 크레덴셜만 삭제 (Auth0 웹 세션은 유지 — 재로그인 시 계정 선택 생략)
    func logout() {
        _ = credentialsManager.clear()
        state = .loggedOut
    }

    /// API 호출용 액세스 토큰 (만료 임박 시 자동 갱신).
    /// 일시적 실패(.transient)와 세션 무효(.sessionInvalid)를 구분해 던진다 —
    /// 호출부는 토큰 없이 요청을 보내지 말고 즉시 실패시켜야 한다.
    func accessToken() async throws -> String {
        do {
            return try await credentialsManager.credentials(minTTL: 60).accessToken
        } catch {
            if Self.isNetworkError(error) {
                throw TokenError.transient
            }
            // 진짜 인증 문제(리프레시 토큰 무효/폐기 등)일 때만 세션 정리
            handleUnauthorized()
            throw TokenError.sessionInvalid
        }
    }

    /// 서버가 401을 반환했을 때 호출 — 크레덴셜을 비우고 로그인 화면으로 전환
    func handleUnauthorized() {
        _ = credentialsManager.clear()
        state = .loggedOut
    }
}
