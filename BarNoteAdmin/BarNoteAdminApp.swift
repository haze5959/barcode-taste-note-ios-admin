import SwiftUI

@main
struct BarNoteAdminApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// 인증 상태에 따라 로그인/메인 화면을 전환하는 루트 뷰
struct RootView: View {
    private let auth = AuthManager.shared

    var body: some View {
        Group {
            switch auth.state {
            case .checking:
                ProgressView("로그인 확인 중...")
            case .loggedOut:
                LoginView()
            case .loggedIn:
                MainTabView()
            }
        }
        .task {
            if auth.state == .checking {
                await auth.bootstrap()
            }
        }
    }
}
