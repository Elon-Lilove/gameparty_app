import SwiftUI
import UIKit
import UserNotifications

/// 使用上传的整屏设计图作为通知预授权页。
struct NotificationPermissionView: View {
    var onFinished: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var isResolvingStatus = true
    @State private var isRequesting = false
    @State private var isSettingsAlertVisible = false
    @State private var requestErrorMessage: String?
    @State private var completionGate = NotificationPermissionCompletionGate()

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            ZStack {
                Color(red: 0.98, green: 0.96, blue: 0.93)
                    .ignoresSafeArea()

                PartyGamesResourceImage.image("NotificationPermissionHero")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()

                // 可点热区：盖在设计图按钮位置上
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    Button {
                        HapticService.medium()
                        Task { await allowNotifications() }
                    } label: {
                        ZStack {
                            Color.white.opacity((isRequesting || isResolvingStatus) ? 0.12 : 0.001)
                            if isRequesting || isResolvingStatus {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(.white)
                                    Text(isResolvingStatus ? "检查权限…" : "处理中…")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .frame(height: max(56, h * 0.075))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRequesting || isResolvingStatus)
                    .accessibilityLabel((isRequesting || isResolvingStatus) ? "正在检查通知权限" : "允许通知")
                    .padding(.horizontal, proxy.size.width * 0.08)

                    Button {
                        finish(markDeferred: true)
                    } label: {
                        Text("或许以后")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.48))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(44, h * 0.055))
                            .background(Color(red: 0.98, green: 0.96, blue: 0.93))
                    }
                    .disabled(isRequesting || isResolvingStatus)
                    .padding(.bottom, max(12, proxy.safeAreaInsets.bottom))
                }
            }
        }
        .ignoresSafeArea()
        .task {
            await NotificationPermissionStore.refreshSystemAuthorizationAndCompleteIfNeeded()
            isResolvingStatus = false
            if !NotificationPermissionStore.shouldShowPrompt {
                finish()
                return
            }
            await NetworkWarmup.run()
        }
        .alert("通知权限已关闭", isPresented: $isSettingsAlertVisible) {
            Button("以后再说", role: .cancel) {
                finish(markCompleted: true)
            }
            Button("前往设置") {
                finish(markCompleted: true) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }
        } message: {
            Text("请在系统设置中允许 PartyGames 发送通知。")
        }
        .alert("暂时无法请求通知", isPresented: requestErrorBinding) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(requestErrorMessage ?? "请稍后重试")
        }
    }

    private func allowNotifications() async {
        guard !isRequesting else { return }
        isRequesting = true
        requestErrorMessage = nil
        defer { isRequesting = false }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch NotificationPermissionStore.nextStep(for: settings.authorizationStatus) {
        case .finish:
            finish(markCompleted: true)
        case .openSettings:
            isSettingsAlertVisible = true
        case .request:
            do {
                _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                let refreshed = await center.notificationSettings()
                switch NotificationPermissionStore.nextStep(for: refreshed.authorizationStatus) {
                case .finish:
                    finish(markCompleted: true)
                case .openSettings, .request:
                    isSettingsAlertVisible = true
                }
            } catch {
                requestErrorMessage = error.localizedDescription
            }
        }
    }

    private func finish(
        markCompleted: Bool = false,
        markDeferred: Bool = false,
        beforeCallback: () -> Void = {}
    ) {
        guard completionGate.claim() else { return }
        if markCompleted {
            NotificationPermissionStore.markCompleted()
        } else if markDeferred {
            NotificationPermissionStore.markDeferred()
        }
        beforeCallback()
        onFinished()
    }

    private var requestErrorBinding: Binding<Bool> {
        Binding(
            get: { requestErrorMessage != nil },
            set: { if !$0 { requestErrorMessage = nil } }
        )
    }
}
