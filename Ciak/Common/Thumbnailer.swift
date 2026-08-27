import AVFoundation
import SwiftUI
import UIKit

/// Genera e conserva le miniature delle clip, così la libreria resta scorrevole.
enum Thumbnailer {
    private static let cache = NSCache<NSString, UIImage>()

    static func cacheURL(for clipID: UUID) -> URL {
        LibraryStore.thumbsDirectory.appendingPathComponent("\(clipID.uuidString).jpg")
    }

    static func cached(for clipID: UUID) -> UIImage? {
        if let image = cache.object(forKey: clipID.uuidString as NSString) { return image }
        guard let data = try? Data(contentsOf: cacheURL(for: clipID)),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: clipID.uuidString as NSString)
        return image
    }

    static func thumbnail(for videoURL: URL, clipID: UUID) async -> UIImage? {
        if let existing = cached(for: clipID) { return existing }

        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        // Un fotogramma a mezzo secondo evita il nero iniziale di molte riprese.
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        guard let cgImage = try? await generator.image(at: time).image else { return nil }

        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: clipID.uuidString as NSString)
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: cacheURL(for: clipID), options: .atomic)
        }
        return image
    }
}

/// Miniatura asincrona con segnaposto.
struct ClipThumbnail: View {
    let clip: Clip
    let url: URL
    var cornerRadius: CGFloat = 10

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .overlay(Image(systemName: "film").foregroundStyle(.secondary))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: clip.id) {
            image = await Thumbnailer.thumbnail(for: url, clipID: clip.id)
        }
    }
}
