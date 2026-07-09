import SwiftUI

/// 메인 탭: 대시보드 / 제품 / 노트 / 신고 / 관리
struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("대시보드", systemImage: "chart.bar.fill")
            }

            NavigationStack {
                ProductsView()
            }
            .tabItem {
                Label("제품", systemImage: "shippingbox.fill")
            }

            NavigationStack {
                NotesView()
            }
            .tabItem {
                Label("노트", systemImage: "note.text")
            }

            NavigationStack {
                ReportsView()
            }
            .tabItem {
                Label("신고", systemImage: "exclamationmark.bubble.fill")
            }

            NavigationStack {
                ManageView()
            }
            .tabItem {
                Label("관리", systemImage: "gearshape.fill")
            }
        }
    }
}

/// 관리 탭: 미참조 이미지 / 실패 바코드 / 로그아웃
struct ManageView: View {
    private let auth = AuthManager.shared
    @State private var showLogoutConfirm = false

    var body: some View {
        List {
            Section("관리 도구") {
                NavigationLink {
                    DeletedImagesView()
                } label: {
                    Label("미참조 이미지", systemImage: "photo.on.rectangle.angled")
                }

                NavigationLink {
                    BarcodeFailuresView()
                } label: {
                    Label("실패 바코드", systemImage: "barcode.viewfinder")
                }

                NavigationLink {
                    BarcodeScansView()
                } label: {
                    Label("바코드 스캔 현황", systemImage: "chart.line.uptrend.xyaxis")
                }
            }

            Section("계정") {
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            Section {
                LabeledContent("버전") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                }
            }
        }
        .navigationTitle("관리")
        .confirmationDialog("로그아웃하시겠습니까?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("로그아웃", role: .destructive) {
                auth.logout()
            }
            Button("취소", role: .cancel) {}
        }
    }
}
