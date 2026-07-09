import SwiftUI

/// 신고 목록 + 답변 — 어드민 웹 ReportsList 미러링
struct ReportsView: View {
    @State private var reports: [Report] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedReport: Report?

    var body: some View {
        List {
            ForEach(reports) { report in
                Button {
                    selectedReport = report
                } label: {
                    ReportRow(report: report)
                }
                .foregroundStyle(.primary)
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }

            if !isLoading && reports.isEmpty {
                ContentUnavailableView(
                    "신고가 없습니다",
                    systemImage: "checkmark.shield",
                    description: Text("접수된 신고가 없습니다.")
                )
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle("🚩 신고 관리")
        .refreshable { await load() }
        .task {
            if reports.isEmpty {
                isLoading = true
                await load()
                isLoading = false
            }
        }
        .sheet(item: $selectedReport) { report in
            ReportDetailSheet(report: report) {
                Task { await load() }
            }
        }
        .errorAlert($errorMessage)
    }

    private func load() async {
        do {
            reports = try await AdminAPI.getReports()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 신고 목록 행
struct ReportRow: View {
    let report: Report

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TagView(text: report.typeLabel, color: .orange)
                Spacer()
                if report.isReplied {
                    TagView(text: "답변 완료", color: .green)
                } else {
                    TagView(text: "대기 중", color: .gray)
                }
            }

            Text(report.body)
                .font(.subheadline)
                .lineLimit(2)

            Text(DateLabel.display(report.registered))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

/// 신고 상세 + 답변 작성 시트
struct ReportDetailSheet: View {
    let report: Report
    let onReplied: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var reply: String = ""
    @State private var targetUser: UserDetailResponse?
    @State private var targetProduct: ProductInfo?
    @State private var isDetailLoading = false
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("신고 내용") {
                    HStack {
                        TagView(text: report.typeLabel, color: .orange)
                        Spacer()
                        Text(DateLabel.display(report.registered))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(report.body)
                        .font(.subheadline)
                }

                Section("신고 유저") {
                    if let targetUser {
                        LabeledContent("닉네임", value: targetUser.user.nickName ?? "-")
                        LabeledContent("노트 수", value: "\(targetUser.noteCount ?? 0)개")
                        LabeledContent("팔로워 수", value: "\(targetUser.followerCount ?? 0)명")
                    } else if isDetailLoading {
                        ProgressView()
                    } else {
                        Text("유저 정보를 불러올 수 없습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("유저 ID") {
                        Text(report.userId)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                // 기타(type == 1) 신고는 제품 정보가 없음 (웹과 동일)
                if report.type != 1 {
                    Section("신고 제품") {
                        if let targetProduct {
                            HStack(spacing: 12) {
                                RemoteImage(url: targetProduct.imageIds?.first.flatMap { C.imageURL($0) })
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(targetProduct.product.name)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(2)
                                    TagView(
                                        text: ProductTypeLabel.label(for: targetProduct.product.type),
                                        color: .blue
                                    )
                                }
                            }
                        } else if isDetailLoading {
                            ProgressView()
                        } else {
                            Text("제품 정보를 불러올 수 없습니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("제품 ID") {
                            Text(report.productId)
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                Section("관리자 답변") {
                    TextField("답변 내용을 입력해주세요.", text: $reply, axis: .vertical)
                        .lineLimit(4...10)

                    Button {
                        Task { await sendReply() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSending {
                                ProgressView()
                            } else {
                                Label(report.isReplied ? "답변 수정" : "답변 등록", systemImage: "paperplane.fill")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSending || reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("신고 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .task { await loadDetails() }
            .errorAlert($errorMessage)
        }
    }

    private func loadDetails() async {
        reply = report.reply ?? ""
        isDetailLoading = true
        // 유저/제품 상세는 실패해도 무시 (웹과 동일하게 .catch(() => null))
        async let userTask = try? AdminAPI.getUserDetail(id: report.userId)
        async let productTask: ProductInfo? = report.type == 1
            ? nil
            : (try? AdminAPI.getProductDetail(id: report.productId))
        (targetUser, targetProduct) = await (userTask, productTask)
        isDetailLoading = false
    }

    private func sendReply() async {
        isSending = true
        defer { isSending = false }
        do {
            try await AdminAPI.updateReport(id: report.id, reply: reply)
            onReplied()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
