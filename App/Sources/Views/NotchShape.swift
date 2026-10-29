import SwiftUI

/// 노치에서 자라 나온 판 모양(시안 v3.5). 위쪽 양 끝은 안쪽으로 오목한 곡선, 아래는 둥근 모서리.
/// 오목 곡선은 판 몸통 바깥 `earRadius`만큼 튀어나오므로 그리는 사각형은 몸통보다 양옆으로 그만큼 넓다.
struct NotchShape: Shape {
    static let earRadius: CGFloat = 8

    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let ear = Self.earRadius
        let bodyLeft = rect.minX + ear
        let bodyRight = rect.maxX - ear
        let bottom = rect.maxY
        let radius = min(bottomRadius, (bodyRight - bodyLeft) / 2, rect.height - ear)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: bodyRight, y: rect.minY),
            tangent2End: CGPoint(x: bodyRight, y: bottom), radius: ear)
        path.addArc(
            tangent1End: CGPoint(x: bodyRight, y: bottom),
            tangent2End: CGPoint(x: bodyLeft, y: bottom), radius: radius)
        path.addArc(
            tangent1End: CGPoint(x: bodyLeft, y: bottom),
            tangent2End: CGPoint(x: bodyLeft, y: rect.minY), radius: radius)
        path.addArc(
            tangent1End: CGPoint(x: bodyLeft, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: ear)
        path.closeSubpath()
        return path
    }
}

/// 노치 구멍(카메라 자리)의 크기. 접힌 판은 구멍 양옆에 내용을 둔다.
struct NotchMetrics: Equatable {
    var holeWidth: CGFloat
    var height: CGFloat
}
