import SwiftUI

struct SharedPurchaseItemRow: View {
    @Environment(\.self) private var environment
    let item: SharedItem
    let isSelected: Bool
    let canSelect: Bool
    let canChange: Bool
    @AccessibilityFocusState.Binding var focusedProductID: UUID?
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Button(action: onSelect) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(isSelected ? Color.onPrimary : .border, .appPrimary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.headline)
                            .foregroundStyle(.textPrimary)
                        if let quantity = item.quantity {
                            Text(quantity)
                                .font(.subheadline)
                                .foregroundStyle(.textSecondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSelect)
            .accessibilityValue(isSelected ? Text("Selected") : Text("Not selected"))
            .accessibilityHint("Changes the local selection. The purchase is saved when you tap Confirm purchase.")
            .accessibilityFocused($focusedProductID, equals: item.id)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canChange {
                // Resolve symbol colors in the row's appearance before the native actions capture their images.
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .renderingMode(.original)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color(Color.danger.resolve(in: environment)))
                }
                .accessibilityLabel("Remove")
                .tint(.dangerSoft)
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .renderingMode(.original)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color(Color.onPrimary.resolve(in: environment)))
                }
                .accessibilityLabel("Edit")
                .tint(.appPrimary)
            }
        }
    }
}

#Preview("Pending product", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    @Previewable @AccessibilityFocusState var focusedProductID: UUID?
    if let item = viewModel.items.first {
        Form {
            SharedPurchaseItemRow(
                item: item,
                isSelected: true,
                canSelect: true,
                canChange: true,
                focusedProductID: $focusedProductID
            ) {} onEdit: {} onRemove: {}
            .listRowBackground(Color.primarySoft)
        }
        .modifier(ShoppingFormStyle())
    }
}
