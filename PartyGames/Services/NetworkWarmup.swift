import Foundation

enum NetworkWarmup {
    /// 轻量探测：触发中国区「无线数据」系统弹窗，并预热麻将 API。
    static func run() async {
        let candidates = [
            URL(string: "https://party-games-mahjong-join.netlify.app/api/health"),
            URL(string: "https://mahjong-score-worker.d03054144.workers.dev/health"),
        ].compactMap { $0 }

        for url in candidates {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 8
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    return
                }
            } catch {
                continue
            }
        }
    }
}
