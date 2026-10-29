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
        guard let pixels = SnapshotPixels(png: png) else { return "PNG를 읽지 못했다" }
        let expected = (Int(size.width) * snapshotScale, Int(size.height) * snapshotScale)
        guard pixels.width == expected.0, pixels.height == expected.1 else {
            return "픽셀 크기 \(pixels.width)×\(pixels.height), 기대 \(expected.0)×\(expected.1)"
        }
        return nil
    }

    /// 노치 판: 판 안(`board` 지점, pt) 색이 테마와 무관하고 판 밖 바탕과 다르며, 판 안에 바탕 말고 그린 것이 있는지.
    /// 노치 판은 테마와 상관없이 같은 색이라, 라이트·다크가 같은 픽셀만 모으면 판 안만 남는다
    /// (판 밖 바탕과 판 가장자리 안티앨리어싱은 테마마다 다르다). 거기에 판 바탕색 말고 다른 색이 있어야 한다.
    static func notchBoardIssue(light: Data, dark: Data, board: CGPoint) -> String? {
        guard let light = SnapshotPixels(png: light), let dark = SnapshotPixels(png: dark) else {
            return "PNG를 읽지 못했다"
        }
        guard light.width == dark.width, light.height == dark.height else { return "라이트와 다크 크기가 다르다" }
        let lightBoard = light.dominantColor(around: board)
        let darkBoard = dark.dominantColor(around: board)
        guard lightBoard == darkBoard else {
            return "노치 판 안 색이 테마에 따라 다르다(라이트 \(lightBoard), 다크 \(darkBoard))"
        }
        if let issue = boardOutsideIssue(light: light, dark: dark, lightBoard: lightBoard, darkBoard: darkBoard) {
            return issue
        }
        var drawn = 0
        for y in 0..<light.height {
            for x in 0..<light.width {
                let color = light[x, y]
                if color == dark[x, y], color != lightBoard { drawn += 1 }
            }
        }
        // 점 하나(약 6pt 지름)도 2배 배율에서 수십 픽셀이다.
        guard drawn >= minimumDrawnPixels else { return "노치 판 안에 바탕 말고 그린 것이 없다(\(drawn)px)" }
        return nil
    }

    /// 떠 있는 창: 판 안(`board` 지점, pt) 색이 판 밖 바탕과 다르고 라이트와 다크에서 다른지.
    static func floatingBoardIssue(light: Data, dark: Data, board: CGPoint) -> String? {
        guard let light = SnapshotPixels(png: light), let dark = SnapshotPixels(png: dark) else {
            return "PNG를 읽지 못했다"
        }
        let lightBoard = light.dominantColor(around: board)
        let darkBoard = dark.dominantColor(around: board)
        if let issue = boardOutsideIssue(light: light, dark: dark, lightBoard: lightBoard, darkBoard: darkBoard) {
            return issue
        }
        guard lightBoard != darkBoard else { return "떠 있는 창 판 안 색이 라이트와 다크에서 같다(\(lightBoard))" }
        return nil
    }

    private static let minimumDrawnPixels = 20

    /// 판 안 색이 판 밖 바탕(왼쪽 위 모서리, 어느 상태든 판 밖)과 같으면 판이 그려지지 않은 것이다.
    private static func boardOutsideIssue(
        light: SnapshotPixels, dark: SnapshotPixels, lightBoard: SnapshotPixels.RGBA, darkBoard: SnapshotPixels.RGBA
    ) -> String? {
        if lightBoard == light[0, 0] { return "라이트: 판 안 색이 판 밖 바탕과 같다(\(lightBoard))" }
        if darkBoard == dark[0, 0] { return "다크: 판 안 색이 판 밖 바탕과 같다(\(darkBoard))" }
        return nil
    }
}

/// PNG를 RGBA 8비트 배열로 푼 것. 위 줄이 0번 행이다.
struct SnapshotPixels {
    struct RGBA: Hashable, CustomStringConvertible {
        var r, g, b, a: UInt8
        var description: String { String(format: "#%02X%02X%02X%02X", r, g, b, a) }
    }

    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(png: Data) {
        guard let image = NSBitmapImageRep(data: png)?.cgImage else { return nil }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    subscript(x: Int, y: Int) -> RGBA {
        let i = (y * width + x) * 4
        return RGBA(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2], a: bytes[i + 3])
    }

    /// `point`(pt) 둘레 8×8pt에서 가장 많은 색. 글자나 점이 걸려도 판 바탕색이 나온다.
    func dominantColor(around point: CGPoint) -> RGBA {
        let half = 4 * snapshotScale
        let cx = Int(point.x) * snapshotScale
        let cy = Int(point.y) * snapshotScale
        var counts: [RGBA: Int] = [:]
        for y in max(0, cy - half)..<min(height, cy + half) {
            for x in max(0, cx - half)..<min(width, cx + half) {
                counts[self[x, y], default: 0] += 1
            }
        }
        return counts.max { $0.value < $1.value }?.key ?? self[cx, cy]
    }
}
