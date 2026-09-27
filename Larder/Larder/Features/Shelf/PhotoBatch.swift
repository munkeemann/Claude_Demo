import PhotosUI
import SwiftUI

/// A list section that collects photos for one scan: take several with the
/// camera, pick several from the library, remove any before scanning.
/// Pair it with `.photoBatch(...)` on the screen, which presents the camera
/// and loads library picks.
struct PhotoBatchSection: View {
    @Binding var photos: [UIImage]
    @Binding var pickerItems: [PhotosPickerItem]
    @Binding var isShowingCamera: Bool
    var maxCount: Int = PhotoBatch.maxCount
    var footer: String

    var body: some View {
        Section {
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 92, height: 92)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        photos.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(Color.white, Color.black.opacity(0.55))
                                    }
                                    .buttonStyle(.borderless)
                                    .padding(4)
                                    .accessibilityLabel("Remove photo \(index + 1)")
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if CameraPicker.isAvailable {
                Button {
                    isShowingCamera = true
                } label: {
                    Label(photos.isEmpty ? "Take a Photo" : "Take Another Photo", systemImage: "camera")
                }
                .disabled(photos.count >= maxCount)
            }
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: max(1, maxCount - photos.count),
                matching: .images
            ) {
                Label(photos.isEmpty ? "Choose Photos" : "Add From Library", systemImage: "photo.on.rectangle")
            }
            .disabled(photos.count >= maxCount)
        } footer: {
            Text(footer)
        }
    }
}

enum PhotoBatch {
    static let maxCount = 8

    /// JPEGs for Claude. Big batches are sent a little smaller.
    static func jpegs(from photos: [UIImage]) -> [Data] {
        let edge: CGFloat = photos.count > 4 ? 2048 : ShelfPhoto.maxLongEdge
        return photos.compactMap { ShelfPhoto.jpegData(from: $0, maxLongEdge: edge) }
    }
}

private struct PhotoBatchPresenter: ViewModifier {
    @Binding var photos: [UIImage]
    @Binding var pickerItems: [PhotosPickerItem]
    @Binding var isShowingCamera: Bool
    var maxCount: Int

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraPicker { image in
                    isShowingCamera = false
                    if photos.count < maxCount { photos.append(image) }
                } onCancel: {
                    isShowingCamera = false
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                let selected = items
                pickerItems = []
                Task {
                    for item in selected {
                        guard photos.count < maxCount,
                              let data = try? await item.loadTransferable(type: Data.self),
                              let image = UIImage(data: data)
                        else { continue }
                        photos.append(image)
                    }
                }
            }
    }
}

extension View {
    /// Presents the camera and loads library picks for a `PhotoBatchSection`.
    func photoBatch(
        _ photos: Binding<[UIImage]>,
        pickerItems: Binding<[PhotosPickerItem]>,
        isShowingCamera: Binding<Bool>,
        maxCount: Int = PhotoBatch.maxCount
    ) -> some View {
        modifier(PhotoBatchPresenter(photos: photos, pickerItems: pickerItems, isShowingCamera: isShowingCamera, maxCount: maxCount))
    }
}
