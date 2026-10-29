import SwiftUI

/// 시안 S3 아이콘(넓은 잔 + 김 한 줄, 24 격자). 원본은 시안 HTML의 `#s-drop` SVG.
struct CupIcon: View {
    /// 잔 몸통(그릇 위 y 9 ~ 받침 아래 y 22)의 세로 가운데, 24 격자 높이에 대한 비율. 김은 뺀다.
    nonisolated static let bodyCenterFraction: CGFloat = 15.5 / 24

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            context.scaleBy(x: scale, y: scale)
            context.stroke(
                Self.steam, with: .foreground,
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            context.fill(Self.cup, with: .foreground)
            context.fill(
                Path(roundedRect: CGRect(x: 6.2, y: 20.2, width: 11.6, height: 1.8), cornerRadius: 0.9),
                with: .foreground)
        }
    }

    private static let steam = Path { path in
        path.move(to: CGPoint(x: 12.6, y: 2.4))
        path.addCurve(
            to: CGPoint(x: 12.0, y: 6.6),
            control1: CGPoint(x: 10.9, y: 3.7), control2: CGPoint(x: 13.7, y: 4.9))
    }

    private static let cup = Path { path in
        path.move(to: CGPoint(x: 4.2, y: 9))
        path.addLine(to: CGPoint(x: 19.8, y: 9))
        path.addLine(to: CGPoint(x: 19.8, y: 11.4))
        path.addArc(
            tangent1End: CGPoint(x: 19.8, y: 19.2), tangent2End: CGPoint(x: 12, y: 19.2), radius: 7.8)
        path.addArc(
            tangent1End: CGPoint(x: 4.2, y: 19.2), tangent2End: CGPoint(x: 4.2, y: 11.4), radius: 7.8)
        path.closeSubpath()
    }
}
