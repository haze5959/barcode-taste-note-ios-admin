import SwiftUI

struct LoginView: View {
    private let auth = AuthManager.shared
    @State private var isLoggingIn = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "wineglass.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("BarNote Admin")
                .font(.largeTitle.bold())

            Text("바노트 관리자 전용 앱입니다.\n관리자 계정으로 로그인해 주세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button {
                Task {
                    isLoggingIn = true
                    await auth.login()
                    isLoggingIn = false
                }
            } label: {
                HStack {
                    if isLoggingIn {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "person.badge.key.fill")
                    }
                    Text("Google로 로그인")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoggingIn)
        }
        .padding(24)
        .errorAlert(Binding(
            get: { auth.loginErrorMessage },
            set: { auth.loginErrorMessage = $0 }
        ))
    }
}
