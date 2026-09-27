import SwiftData
import SwiftUI

/// "Saved 12 changes · Undo", shown for a few seconds after a batch change.
struct UndoBanner: View {
    @Environment(\.modelContext) private var modelContext
    private var center: UndoCenter { .shared }

    var body: some View {
        ZStack {
            if let offer = center.offer {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.green)
                    Text(offer.message)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.primary)
                    Spacer(minLength: 8)
                    Button("Undo", action: undo)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.green)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
                .padding(.horizontal)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(offer.id)
            }
        }
        .animation(.spring(duration: 0.3), value: center.offer?.id)
    }

    private func undo() {
        let context = modelContext
        try? center.undo(context: context)
        Task { await Reminders.refresh(context: context) }
    }
}
