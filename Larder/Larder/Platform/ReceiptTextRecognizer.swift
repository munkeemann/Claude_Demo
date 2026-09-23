import Foundation
import ImageIO
import InventoryCore
import UIKit
import Vision

/// Runs Vision text recognition on receipt images and rebuilds the rows.
enum ReceiptTextRecognizer {
    /// OCR for every page, joined into one text block in page order.
    static func text(from images: [UIImage]) async throws -> String {
        var pages: [[RecognizedTextFragment]] = []
        for image in images {
            guard let cgImage = image.cgImage else { continue }
            pages.append(try await fragments(in: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation)))
        }
        return OCRLineAssembler.text(fromPages: pages)
    }

    static func fragments(in image: CGImage, orientation: CGImagePropertyOrientation) async throws -> [RecognizedTextFragment] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // Language correction "fixes" receipt abbreviations; keep raw text.
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
            try handler.perform([request])
            return (request.results ?? []).compactMap { observation -> RecognizedTextFragment? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox
                return RecognizedTextFragment(
                    text: candidate.string,
                    x: Double(box.minX),
                    y: Double(box.minY),
                    width: Double(box.width),
                    height: Double(box.height),
                    confidence: Double(candidate.confidence)
                )
            }
        }.value
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
