import SwiftUI
import UIKit

/// 毛豆联网加载页：保留原插画气质，用 SwiftUI 原生动效让角色“跑起来”。
struct MahjongConnectingView: View {
    @Bindable var viewModel: MahjongScoreViewModel
    var onClose: () -> Void

    @State private var progress: Double = 0.08
    @State private var isRunning = false
    @State private var didFail = false
    @State private var progressTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.995, green: 0.965, blue: 0.925),
                        Color(red: 0.985, green: 0.95, blue: 0.91)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                    .ignoresSafeArea()

                LoadingConfetti(isRunning: isRunning && !didFail)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    LoadingMascotRunner(isRunning: isRunning && !didFail)
                        .frame(width: min(286, proxy.size.width * 0.72), height: 302)
                        .padding(.bottom, max(24, proxy.size.height * 0.03))

                    loadingControls(width: proxy.size.width, bottomInset: proxy.safeAreaInsets.bottom)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isRunning = true
            await startConnecting()
        }
        .onDisappear {
            isRunning = false
            progressTask?.cancel()
        }
    }

    @ViewBuilder
    private func loadingControls(width: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(spacing: 12) {
            Text(didFail ? "网络连接似乎出现问题" : "毛豆正在努力加载中...")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.88))

            if didFail {
                Text("请退出后重试")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.45))

                Button {
                    onClose()
                } label: {
                    Text("返回")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 160, height: 48)
                        .background(Color.black.opacity(0.82))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.hapticPlain)
                .padding(.top, 8)
            } else {
                LoadingProgressBar(progress: progress)
                    .frame(width: min(268, width * 0.68), height: 24)

                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, max(36, bottomInset + 24))
    }

    private func startConnecting() async {
        didFail = false
        progress = 0.08
        isRunning = true
        startFakeProgress()

        var lastError: Error?
        for attempt in 1...5 {
            do {
                try await viewModel.createMultiplayerRoomThrowing()
                guard !Task.isCancelled else { return }
                progressTask?.cancel()
                withAnimation(.easeOut(duration: 0.2)) {
                    progress = 1
                }
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                onClose()
                return
            } catch {
                guard !Task.isCancelled else { return }
                lastError = error
                if attempt < 5 {
                    try? await Task.sleep(for: .milliseconds(800))
                }
            }
        }

        guard !Task.isCancelled else { return }
        progressTask?.cancel()
        didFail = true
        isRunning = false
        if let lastError {
            viewModel.errorMessage = MahjongScoreViewModel.friendlyNetworkError(lastError)
        }
    }

    private func startFakeProgress() {
        progressTask?.cancel()
        progressTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                let next = min(0.9, progress + Double.random(in: 0.01...0.035))
                progress = next
                if next >= 0.9 { return }
            }
        }
    }
}

private struct LoadingMascotRunner: View {
    let isRunning: Bool

    @State private var stride = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Color.black.opacity(stride && isRunning ? 0.16 : 0.11))
                .frame(width: stride && isRunning ? 136 : 110, height: stride && isRunning ? 18 : 12)
                .blur(radius: 3)
                .offset(x: stride && isRunning ? -8 : 8, y: -16)
                .animation(runningAnimation(duration: 0.34), value: stride)

            DustTrail(isRunning: isRunning)
                .offset(x: 92, y: -44)

            mascotImage
                .frame(width: 250, height: 258)
                .scaleEffect(0.88)
                .rotationEffect(.degrees(stride && isRunning ? -4 : 4), anchor: .bottom)
                .offset(x: stride && isRunning ? -8 : 8, y: stride && isRunning ? -20 : -7)
                .animation(runningAnimation(duration: 0.34), value: stride)
        }
        .onAppear {
            stride = true
        }
        .onChange(of: isRunning) { _, newValue in
            if newValue {
                stride.toggle()
            }
        }
    }

    @ViewBuilder
    private var mascotImage: some View {
        if let image = Self.croppedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            PartyGamesResourceImage.image("MahjongLoadingMascot")
                .resizable()
                .scaledToFit()
        }
    }

    private func runningAnimation(duration: Double) -> Animation? {
        isRunning ? .easeInOut(duration: duration).repeatForever(autoreverses: true) : .easeOut(duration: 0.2)
    }

    private static let croppedImage = makeCroppedMascotImage()

    private static func makeCroppedMascotImage() -> UIImage? {
        guard let image = PartyGamesResourceImage.uiImage("MahjongLoadingMascot"),
              let cgImage = image.cgImage else {
            return nil
        }

        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height
        let cropRect = CGRect(x: 70, y: 300, width: 360, height: 365)
            .applying(CGAffineTransform(scaleX: scaleX, y: scaleY))
            .integral

        guard let cropped = cgImage.cropping(to: cropRect) else {
            return image
        }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}

private struct DustTrail: View {
    let isRunning: Bool

    @State private var puff = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(Color.black.opacity(0.75), lineWidth: 3)
                    .background(Circle().fill(Color.white.opacity(0.94)))
                    .frame(width: puff && isRunning ? CGFloat(18 + index * 6) : CGFloat(10 + index * 4))
                    .opacity(puff && isRunning ? 0.06 : 0.32)
                    .offset(
                        x: puff && isRunning ? CGFloat(18 + index * 18) : CGFloat(index * 10),
                        y: CGFloat(index * -7)
                    )
                    .animation(
                        isRunning
                            ? .easeOut(duration: 0.58).repeatForever(autoreverses: false).delay(Double(index) * 0.08)
                            : .easeOut(duration: 0.2),
                        value: puff
                    )
            }
        }
        .frame(width: 100, height: 60, alignment: .leading)
        .onAppear {
            puff = true
        }
        .onChange(of: isRunning) { _, newValue in
            if newValue {
                puff.toggle()
            }
        }
    }
}

private struct LoadingConfetti: View {
    let isRunning: Bool

    @State private var float = false

    private let items: [(x: CGFloat, y: CGFloat, color: Color, size: CGFloat)] = [
        (-138, -214, Color(red: 0.98, green: 0.78, blue: 0.28), 12),
        (128, -214, Color(red: 0.48, green: 0.77, blue: 0.56), 10),
        (-96, -104, Color(red: 0.55, green: 0.79, blue: 0.68), 7),
        (118, -92, Color(red: 0.94, green: 0.55, blue: 0.62), 9),
        (-156, 8, Color(red: 0.97, green: 0.83, blue: 0.36), 8)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "heart.fill")
                        .font(.system(size: item.size, weight: .bold))
                        .foregroundStyle(item.color.opacity(0.44))
                        .rotationEffect(.degrees(float && isRunning ? 10 : -10))
                        .position(
                            x: proxy.size.width / 2 + item.x,
                            y: proxy.size.height * 0.36 + item.y + (float && isRunning ? -8 : 8)
                        )
                        .animation(
                            isRunning
                                ? .easeInOut(duration: 1.35 + Double(index) * 0.12).repeatForever(autoreverses: true)
                                : .easeOut(duration: 0.2),
                            value: float
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            float = true
        }
        .onChange(of: isRunning) { _, newValue in
            if newValue {
                float.toggle()
            }
        }
    }
}

private struct LoadingProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(1, max(0, progress))
            let width = proxy.size.width
            let fillWidth = max(proxy.size.height, width * clampedProgress)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(red: 0.995, green: 0.93, blue: 0.84))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.20, green: 0.76, blue: 0.34),
                                Color(red: 0.42, green: 0.83, blue: 0.42)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth)
                    .animation(.easeOut(duration: 0.16), value: progress)
            }
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.black.opacity(0.86), lineWidth: 3)
            )
        }
    }
}
