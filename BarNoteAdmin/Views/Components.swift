import SwiftUI

// MARK: - 공통 에러 알럿 / 토스트

extension View {
    /// 에러 메시지가 설정되면 알럿으로 표시하고, 닫으면 nil로 초기화
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "오류",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }

    /// 하단 토스트. 메시지가 설정되면 잠시 보여준 뒤 자동으로 사라진다.
    func toast(_ message: Binding<String?>) -> some View {
        overlay(alignment: .bottom) {
            if let text = message.wrappedValue {
                Text(text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.75), in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    // id: 메시지 — 메시지가 교체되면 타이머를 재시작해 새 메시지도 온전히 2초 표시
                    .task(id: text) {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        withAnimation { message.wrappedValue = nil }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: message.wrappedValue)
    }
}

// MARK: - 원격 이미지

/// AsyncImage 래퍼: 로딩 placeholder + 실패 아이콘 처리
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            case .failure:
                ZStack {
                    Color(.systemGray5)
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                }
            default:
                ZStack {
                    Color(.systemGray6)
                    ProgressView()
                }
            }
        }
    }
}

// MARK: - 대시보드 카드

/// 대시보드 지표 카드 (아이콘 + 수치 + 부가 설명)
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var footer: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(value)
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let footer {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 14)
                .fill(color)
                .frame(width: 4)
                .padding(.vertical, 10)
                .padding(.leading, 2)
        }
    }
}

// MARK: - 태그

/// Ant Design Tag 느낌의 작은 라벨
struct TagView: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(color)
    }
}

// MARK: - 검토 필요 마커

/// 아직 검토되지 않은 제품 옆에 표시하는 🔍 마커 (어드민 웹의 "검토가 필요한 제품입니다" 툴팁 미러링)
struct ReviewNeededBadge: View {
    var body: some View {
        Text("🔍")
            .accessibilityLabel("검토 필요")
    }
}

// MARK: - 별점 표시

struct RatingLabel: View {
    /// 서버 rating (0~10). nil이면 "-" 표시.
    let rating: Double?

    var body: some View {
        if let rating {
            HStack(spacing: 2) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                // 웹과 동일하게 10점 만점을 5점 만점으로 환산해 표시
                Text(String(format: "%.1f", rating / 2))
                    .font(.caption.weight(.medium))
            }
        } else {
            Text("-")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - sheet(item:) / fullScreenCover(item:) 어댑터

/// fullScreenCover(item:)로 이미지 뷰어를 띄우기 위한 시작 인덱스 래퍼
struct ImageViewerState: Identifiable {
    let index: Int
    var id: Int { index }
}

/// sheet(item:)로 바코드 문자열을 띄우기 위한 래퍼
struct BarcodeSheetItem: Identifiable {
    let value: String
    var id: String { value }
}

// MARK: - 이미지 전체 화면 뷰어

/// 좌우로 넘길 수 있는 전체 화면 이미지 뷰어
struct ImagePagerView: View {
    let urls: [URL?]
    @State var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    RemoteImage(url: url, contentMode: .fit)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))

            VStack {
                HStack {
                    if urls.count > 1 {
                        Text("\(currentIndex + 1) / \(urls.count)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .padding(16)
                Spacer()
            }
        }
    }
}
