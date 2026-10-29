import AppKit
import SwiftUI

enum SnapshotError: Error {
    case bitmapUnavailable
    case pngEncodingFailed
}

/// 스냅샷 배율. `renderPNG`는 1pt를 2px로 그린다.
let snapshotScale = 2

/// 뷰를 `size`(pt) 크기 PNG로 그린다(ADR-0009, research R8). 2배 해상도로 그린다.
/// `NSHostingView` + `cacheDisplay(in:to:)`라서 `TextField` 같은 AppKit 컨트롤도 실제로 그려진다(`ImageRenderer`는 자리표시).
/// 바탕은 `.frame` 뒤에 칠해 뷰가 덮지 않는 자리(다크 위쪽 투명 띠, T009 주의 1)도 화면 테마의 창 바탕색이 되게 한다.
@MainActor
func renderPNG(view: some View, size: CGSize, appearance: NSAppearance.Name) throws -> Data {
    let root = view
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light)
    let hosting = NSHostingView(rootView: root)
    hosting.appearance = NSAppearance(named: appearance)
    hosting.frame = CGRect(origin: .zero, size: size)
    hosting.layoutSubtreeIfNeeded()

    let scale = snapshotScale
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
    else { throw SnapshotError.bitmapUnavailable }
    rep.size = size
    // 창 바탕색 같은 동적 색은 그릴 때의 현재 모양을 따르므로 그리는 동안 모양을 고정한다.
    NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
    }
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw SnapshotError.pngEncodingFailed
    }
    return png
}

/// 스냅샷 저장 위치. `TEST_RUNNER_MOKA_SNAPSHOT_DIR`(xcodebuild가 접두사를 떼고 `MOKA_SNAPSHOT_DIR`로 넘김)가 있으면 그 폴더,
/// 없으면 저장소 루트의 `.verify/snapshots/001/`(커밋하지 않음, `.gitignore`의 `.verify/`).
enum SnapshotOutput {
    static func directory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["MOKA_SNAPSHOT_DIR"], !path.isEmpty {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        // 이 파일은 <저장소>/App/Tests/MokaAppTests/SnapshotHelper.swift에 있다.
        return URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".verify/snapshots/001", directoryHint: .isDirectory)
    }

    @discardableResult
    static func write(_ png: Data, name: String) throws -> URL {
        let directory = directory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(name).png", directoryHint: .notDirectory)
        try png.write(to: url)
        return url
    }
}

/// 기준 이미지 없이 보는 최소 단언. 그림이 만들어졌는지만 보고 화면이 맞는지는 보지 않는다.
enum SnapshotSanity {
    /// 문제가 없으면 nil, 있으면 이유.
    static func issue(in png: Data) -> String? {
        guard let rep = NSBitmapImageRep(data: png) else { return "PNG를 읽지 못했다" }
        guard rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return "크기가 0이다" }
        let first = rep.colorAt(x: 0, y: 0)
        let step = max(1, min(rep.pixelsWide, rep.pixelsHigh) / 64)
        for y in stride(from: 0, to: rep.pixelsHigh, by: step) {
            for x in stride(from: 0, to: rep.pixelsWide, by: step) where rep.colorAt(x: x, y: y) != first {
                return nil
            }
        }
        return "단색이다"
    }

    /// PNG 픽셀 수가 `size`(pt)에 배율을 곱한 값과 같은지.
    static func sizeIssue(in png: Data, size: CGSize) -> String? {
        nil
    }

    /// 노치 판: 판 안(`board` 지점, pt) 색이 테마와 무관하고 판 밖 바탕과 다르며, 판 안에 바탕 말고 그린 것이 있는지.
    static func notchBoardIssue(light: Data, dark: Data, board: CGPoint) -> String? {
        nil
    }

    /// 떠 있는 창: 판 안(`board` 지점, pt) 색이 판 밖 바탕과 다르고 라이트와 다크에서 다른지.
    static func floatingBoardIssue(light: Data, dark: Data, board: CGPoint) -> String? {
        nil
    }
}
