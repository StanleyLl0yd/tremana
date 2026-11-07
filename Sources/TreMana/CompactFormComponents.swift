import SwiftUI

/// Intrinsically sized, native-feeling form surfaces without Form's
/// automatically scrolling, oversized grouped-section layout.
struct CompactFormSection<Content: View>: View {
    let title: LocalizedStringKey
    private let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.headline)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                content
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
        }
    }
}

struct CompactFormRow<Content: View>: View {
    let title: LocalizedStringKey
    private let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 8)
            content
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .frame(minHeight: 34)
    }
}

