import SwiftUI

/// Visual prototype of the iOS 27 Apple Music landscape full-screen player:
/// artwork on the left, track info + lyrics on the right.
struct PlayerScreen: View {
    private let title = "嘘じゃない"
    private let artist = "ずっと真夜中でいいのに。"

    private let lyrics: [(text: String, opacity: Double)] = [
        ("我侭な合言葉\"\" 口ずさむ習慣なんです", 1.0),
        ("空想のずる休み", 0.45),
        ("好きとかなんとか", 0.22),
        ("どうでもいいようなこと", 0.10),
    ]

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            ZStack {
                background
                HStack(alignment: .center, spacing: height * 0.055) {
                    artwork(side: height * 0.78)
                    details(height: height)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, height * 0.095)
                VStack {
                    grabber(height: height)
                        .padding(.top, height * 0.035)
                    Spacer()
                }
            }
            .ignoresSafeArea()
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [Color(white: 0.10), Color(white: 0.035)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func grabber(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height * 0.006, style: .continuous)
            .fill(Color.white.opacity(0.28))
            .frame(width: height * 0.085, height: height * 0.012)
    }

    private func artwork(side: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.035, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.06, green: 0.07, blue: 0.10),
                            Color(red: 0.02, green: 0.02, blue: 0.04),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Group {
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: side * 0.34, height: side * 0.34)
                    .offset(x: -side * 0.14, y: -side * 0.10)
                RoundedRectangle(cornerRadius: side * 0.05, style: .continuous)
                    .fill(Color(red: 0.95, green: 0.78, blue: 0.16).opacity(0.9))
                    .frame(width: side * 0.30, height: side * 0.16)
                    .rotationEffect(.degrees(-18))
                    .offset(x: side * 0.20, y: side * 0.18)
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: side * 0.006)
                    .frame(width: side * 0.62, height: side * 0.62)
            }
            .clipShape(RoundedRectangle(cornerRadius: side * 0.035, style: .continuous))
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(0.5), radius: side * 0.05, x: 0, y: side * 0.02)
    }

    private func details(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: height * 0.055) {
            HStack(alignment: .center, spacing: height * 0.03) {
                VStack(alignment: .leading, spacing: height * 0.008) {
                    Text(title)
                        .font(.system(size: height * 0.058, weight: .bold))
                        .foregroundColor(.white)
                    Text(artist)
                        .font(.system(size: height * 0.042, weight: .regular))
                        .foregroundColor(.white.opacity(0.62))
                }
                Spacer(minLength: 0)
                Image(systemName: "star")
                    .font(.system(size: height * 0.052, weight: .regular))
                    .foregroundColor(.white)
                Image(systemName: "ellipsis")
                    .font(.system(size: height * 0.048, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: height * 0.038) {
                ForEach(Array(lyrics.enumerated()), id: \.offset) { index, line in
                    Text(line.text)
                        .font(.system(size: height * 0.052,
                                      weight: index == 0 ? .semibold : .regular))
                        .foregroundColor(.white.opacity(line.opacity))
                        .blur(radius: index < 2 ? 0 : height * 0.004 * Double(index - 1))
                }
            }
        }
    }
}

struct PlayerScreen_Previews: PreviewProvider {
    static var previews: some View {
        PlayerScreen()
            .previewInterfaceOrientation(.landscapeLeft)
            .preferredColorScheme(.dark)
    }
}
