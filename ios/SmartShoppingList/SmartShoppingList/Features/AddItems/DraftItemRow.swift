import SwiftUI

/// Identifies the action independently from the product row used by ForEach.
enum DraftItemAccessibilityTarget: Hashable {
    case edit(UUID)
}

struct DraftItemRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var sectionSpacing: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var detailSpacing: CGFloat = 4
    @ScaledMetric(relativeTo: .body) private var verticalPadding: CGFloat = 4

    let item: ShoppingDraftItem
    let accessibilityFocus: AccessibilityFocusState<DraftItemAccessibilityTarget?>.Binding
    let onEdit: () -> Void
    let onRemove: () -> Void

    private var layout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            AnyLayout(VStackLayout(alignment: .leading, spacing: sectionSpacing))
        } else {
            AnyLayout(HStackLayout(alignment: .center, spacing: sectionSpacing))
        }
    }

    var body: some View {
        layout {
            VStack(alignment: .leading, spacing: detailSpacing) {
                if item.name.isEmpty {
                    Text("Unnamed product")
                        .font(.headline)
                        .foregroundStyle(.textPrimary)
                } else {
                    Text(item.name)
                        .font(.headline)
                        .foregroundStyle(.textPrimary)
                }

                if !item.quantity.isEmpty {
                    Text(item.quantity)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.textSecondary)
                        .accessibilityLabel("Quantity: \(item.quantity)")
                }

                if item.store.isEmpty {
                    Label("Specify a store", systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.warning)
                } else {
                    Label {
                        Text(item.store)
                    } icon: {
                        Image(systemName: "storefront")
                            .accessibilityHidden(true)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityValue(item.quantity.isEmpty ? Text("Quantity not specified") : Text(""))

            HStack(spacing: 8) {
                Button("Edit", systemImage: "pencil") {
                    onEdit()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(ShoppingIconButtonStyle())
                .accessibilityLabel("Edit \(item.name)")
                .accessibilityFocused(accessibilityFocus, equals: .edit(item.id))
                .id(DraftItemAccessibilityTarget.edit(item.id))
                Button("Remove", systemImage: "trash", role: .destructive) {
                    onRemove()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(ShoppingIconButtonStyle())
                .accessibilityLabel("Remove \(item.name)")
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .lineLimit(nil)
        .padding(.vertical, verticalPadding)
    }
}

#Preview("Draft products", traits: .shoppingDraft) {
    @Previewable @AccessibilityFocusState var focusedControl: DraftItemAccessibilityTarget?
    Form {
        Section {
            ForEach(DraftPreviewSupport.items) { item in
                DraftItemRow(item: item, accessibilityFocus: $focusedControl) {} onRemove: {}
            }
        }
        .listRowBackground(Color.surface)
    }
    .modifier(ShoppingFormStyle())
}

#Preview("Draft products AX5", traits: .shoppingDraft) {
    @Previewable @AccessibilityFocusState var focusedControl: DraftItemAccessibilityTarget?
    Form {
        Section {
            ForEach(DraftPreviewSupport.items) { item in
                DraftItemRow(item: item, accessibilityFocus: $focusedControl) {} onRemove: {}
            }
        }
        .listRowBackground(Color.surface)
    }
    .modifier(ShoppingFormStyle())
    .environment(\.dynamicTypeSize, .accessibility5)
}
