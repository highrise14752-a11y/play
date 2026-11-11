// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

enum PlayerPhoto {
    static let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("player-background.jpg")

    static func replace(with source: URL) async throws {
        try await Task.detached(priority: .utility) {
            let allowed = source.startAccessingSecurityScopedResource()
            defer { if allowed { source.stopAccessingSecurityScopedResource() } }
            guard let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 32 * 1024 * 1024,
                  let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
                  let image = thumbnail(imageSource, size: 1440) else {
                throw PlayError.message("Choose a supported image under 32 MB.")
            }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw PlayError.message("Could not prepare the background image.")
            }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw PlayError.message("Could not save the background image.") }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (data as Data).write(to: file, options: .atomic)
        }.value
    }

    static func thumbnail(_ source: CGImageSource, size: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: size
        ] as CFDictionary)
    }
}

private actor ArtworkPalette {
    static let shared = ArtworkPalette()
    private var cache: [URL: Int] = [:]

    func accent(for url: URL) async -> Int? {
        if let color = cache[url] { return color }
        guard url.scheme == "https",
              let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 8)),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 4_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = PlayerPhoto.thumbnail(source, size: 12) else { return nil }
        var pixels = [UInt8](repeating: 0, count: 12 * 12 * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 12, height: 12, bitsPerComponent: 8,
                                          bytesPerRow: 48, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 12, height: 12))
            return true
        }
        guard drawn else { return nil }
        var bestScore = 0.0
        var best: (Double, Double, Double)?
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 240 {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            let high = max(r, g, b), low = min(r, g, b)
            let score = (high - low) * (1 - abs(high - 0.65))
            if score > bestScore { bestScore = score; best = (r, g, b) }
        }
        guard let color = best else { return nil }
        func byte(_ channel: Double) -> Int { Int((0.22 + channel * 0.78) * 255) }
        let accent = byte(color.0) << 16 | byte(color.1) << 8 | byte(color.2)
        if cache.count >= 40, let first = cache.keys.first { cache.removeValue(forKey: first) }
        cache[url] = accent
        return accent
    }
}

struct ArtworkPaletteWatcher: View {
    @EnvironmentObject private var player: PlaybackController
    @AppStorage("appearance.dynamicAccent") private var enabled = false
    @AppStorage("appearance.artworkAccent") private var accent = -1

    var body: some View {
        let url = enabled ? player.current?.artwork : nil
        Color.clear
            .allowsHitTesting(false)
            .task(id: url) {
                accent = -1
                guard let url = url, let result = await ArtworkPalette.shared.accent(for: url), !Task.isCancelled else { return }
                accent = result
            }
    }
}
