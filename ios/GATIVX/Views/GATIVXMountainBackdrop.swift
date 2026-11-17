import SwiftUI

struct GATIVXMountainBackdrop: View {
    let isNight: Bool
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: isNight
                    ? [Color(red: 0.01, green: 0.06, blue: 0.12), Color(red: 0.02, green: 0.20, blue: 0.31), Color(red: 0.00, green: 0.04, blue: 0.08)]
                    : [Color(red: 0.98, green: 0.88, blue: 0.68), Color(red: 0.70, green: 0.83, blue: 0.89), Color(red: 0.88, green: 0.94, blue: 0.90)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(isNight ? Color.white.opacity(0.8) : Color.orange.opacity(0.28))
                    .frame(width: 48, height: 48).blur(radius: isNight ? 1 : 15)
                    .offset(x: proxy.size.width * 0.31, y: -proxy.size.height * 0.24)
                Canvas { context, size in
                    var far = Path()
                    far.move(to: CGPoint(x: 0, y: size.height * 0.62))
                    far.addLines([
                        CGPoint(x: size.width * 0.18, y: size.height * 0.37),
                        CGPoint(x: size.width * 0.31, y: size.height * 0.53),
                        CGPoint(x: size.width * 0.53, y: size.height * 0.25),
                        CGPoint(x: size.width * 0.72, y: size.height * 0.52),
                        CGPoint(x: size.width * 0.86, y: size.height * 0.35),
                        CGPoint(x: size.width, y: size.height * 0.57),
                        CGPoint(x: size.width, y: size.height),
                        CGPoint(x: 0, y: size.height)
                    ])
                    far.closeSubpath()
                    context.fill(far, with: .linearGradient(Gradient(colors: isNight ? [Color(red: 0.08, green: 0.22, blue: 0.34), .black] : [Color(red: 0.42, green: 0.57, blue: 0.65), Color(red: 0.15, green: 0.34, blue: 0.28)]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                    var near = Path()
                    near.move(to: CGPoint(x: 0, y: size.height * 0.78))
                    near.addLines([CGPoint(x: size.width * 0.22, y: size.height * 0.56), CGPoint(x: size.width * 0.40, y: size.height * 0.72), CGPoint(x: size.width * 0.64, y: size.height * 0.48), CGPoint(x: size.width * 0.82, y: size.height * 0.70), CGPoint(x: size.width, y: size.height * 0.55), CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)])
                    near.closeSubpath()
                    context.fill(near, with: .color(isNight ? Color(red: 0.01, green: 0.09, blue: 0.13).opacity(0.94) : Color(red: 0.15, green: 0.35, blue: 0.24).opacity(0.68)))
                }
                LinearGradient(colors: [.clear, isNight ? .black.opacity(0.42) : .white.opacity(0.18)], startPoint: .center, endPoint: .bottom)
            }
        }
    }
}
