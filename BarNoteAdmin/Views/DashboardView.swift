import SwiftUI

/// 대시보드: 어드민 웹의 지표 카드를 세로 화면에 맞게 2열 그리드로 재구성
struct DashboardView: View {
    @State private var stats: DashboardStats?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            if let stats {
                VStack(alignment: .leading, spacing: 12) {
                    Text("지표 요약")
                        .font(.headline)
                        .padding(.top, 4)

                    LazyVGrid(columns: columns, spacing: 12) {
                        StatCard(
                            title: "총 가입 유저",
                            value: "\((stats.registeredUserCount ?? 0).formatted())명",
                            icon: "person.fill",
                            color: .blue,
                            footer: "최근 30일 가입 \((stats.monthlyRegisteredUserCount ?? 0).formatted())명"
                        )
                        StatCard(
                            title: "구독자",
                            value: "\((stats.premiumUserCount ?? 0).formatted())명",
                            icon: "crown.fill",
                            color: .green,
                            footer: "일일 수익 \(dailyRevenue(stats).formatted())원"
                        )
                        StatCard(
                            title: "최근 30일 노트",
                            value: "\((stats.monthlyNoteCount ?? 0).formatted())개",
                            icon: "calendar",
                            color: .orange,
                            footer: "최근 24시간 \((stats.dailyNoteCount ?? 0).formatted())개"
                        )
                        StatCard(
                            title: "등록된 제품",
                            value: "\((stats.productCount ?? 0).formatted())개",
                            icon: "shippingbox.fill",
                            color: .purple
                        )
                        StatCard(
                            title: "대기 중인 신고",
                            value: "\((stats.notReplyReportCount ?? 0).formatted())건",
                            icon: "exclamationmark.triangle.fill",
                            color: (stats.notReplyReportCount ?? 0) > 0 ? .red : .gray
                        )
                    }

                    activeUsersCard(stats)
                    apiRequestsCard(stats)
                }
                .padding(16)
            } else if isLoading {
                ProgressView("불러오는 중...")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
            } else {
                ContentUnavailableView(
                    "데이터가 없습니다",
                    systemImage: "chart.bar",
                    description: Text("아래로 당겨 새로고침해 주세요.")
                )
                .padding(.top, 80)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("📊 대시보드")
        .refreshable { await load() }
        .task {
            if stats == nil {
                isLoading = true
                await load()
                isLoading = false
            }
        }
        .errorAlert($errorMessage)
    }

    /// 어드민 웹과 동일한 일일 수익 추정: floor((2000 / 30) × 구독자 수)
    private func dailyRevenue(_ stats: DashboardStats) -> Int {
        Int((2000.0 / 30.0 * Double(stats.premiumUserCount ?? 0)).rounded(.down))
    }

    private func activeUsersCard(_ stats: DashboardStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.subheadline)
                    .foregroundStyle(.teal)
                Text("최근 30일 활성 사용자")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            platformRow(icon: "globe", tint: .blue, name: "Web", count: stats.webActiveUsers30d)
            platformRow(icon: "apple.logo", tint: .primary, name: "iOS", count: stats.iosActiveUsers30d)
            platformRow(icon: "candybarphone", tint: .green, name: "Android", count: stats.androidActiveUsers30d)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func platformRow(icon: String, tint: Color, name: String, count: Int?) -> some View {
        HStack {
            Label(name, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
            Spacer()
            Text("\((count ?? 0).formatted())명")
                .font(.subheadline.weight(.semibold))
        }
    }

    private func apiRequestsCard(_ stats: DashboardStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "server.rack")
                    .font(.subheadline)
                    .foregroundStyle(.indigo)
                Text("전날 API 요청 현황")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            apiRow(
                name: "Gemini API",
                success: stats.geminiRequestSuccessCount,
                failure: stats.geminiRequestFailureCount
            )
            Divider()
            apiRow(
                name: "바코드 조회",
                success: stats.barcodeRequestSuccessCount,
                failure: stats.barcodeRequestFailureCount
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func apiRow(name: String, success: Int?, failure: Int?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.subheadline.weight(.semibold))
            HStack {
                Label("성공 \((success ?? 0).formatted())건", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Spacer()
                Label("실패 \((failure ?? 0).formatted())건", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle((failure ?? 0) > 0 ? .red : .secondary)
            }
        }
    }

    private func load() async {
        do {
            stats = try await AdminAPI.getDashboard()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
