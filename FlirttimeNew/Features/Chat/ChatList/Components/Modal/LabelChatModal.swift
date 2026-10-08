import SwiftUI

struct LabelChatModal: View {
    static let labelColors: [String] = [
        "#ea580c",
        "#dc2626",
        "#16a34a",
        "#2563eb",
        "#7c3aed",
        "#db2777",
        "#0891b2",
        "#ca8a04"
    ]

    let chatName: String
    let currentLabel: String?
    let currentColor: String?
    @State private var labelText: String = ""
    @State private var selectedColor: String = LabelChatModal.labelColors[0]
    @State private var showLimitMessage = false
    /// `(labelText, labelColor)` — Remove clears with `("", nil)`.
    let onDone: (String, String?) -> Void
    let onDismiss: () -> Void

    private var trimmedLabel: String {
        labelText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    onDismiss()
                }

            // Modal content
            VStack(spacing: 20) {
                VStack(spacing: 16) {
                    Text(ChatStrings.chat_labelChat.localizedString())
                        .font(.chatSemiBold(size: 28))
                        .foregroundColor(Color.chatTextPrimary)

                    Text(ChatStrings.chat_giveLabelInstruction.localizedString())
                        .font(.chatRegular(size: 12))
                        .foregroundColor(Color.chatTextSecondary)
                        .multilineTextAlignment(.center)
                }

                // Text field
                RTLTextField(ChatStrings.chat_addLabelHere.localizedString(), text: $labelText, fontSize: 16)
                    .frame(height: 25)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.chatPrimary, lineWidth: 1)
                    )
                    .cornerRadius(10)
                    .onChange(of: labelText) { newValue in
                        if newValue.count > 10 {
                            labelText = String(newValue.prefix(10))
                            showLimitMessage = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showLimitMessage = false
                            }
                        }
                    }

                if showLimitMessage {
                    Text("Maximum 10 characters allowed")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                // COLOR picker — selected color is label background
                VStack(alignment: .leading, spacing: 10) {
                    Text("COLOR")
                        .font(.chatMedium(size: 12))
                        .foregroundColor(Color.chatTextSecondary)
                        .kerning(0.6)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 7),
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(Self.labelColors, id: \.self) { colorHex in
                            colorDot(colorHex)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Preview — white text on colored background
                if !trimmedLabel.isEmpty {
                    HStack(spacing: 10) {
                        Text("Preview")
                            .font(.chatRegular(size: 14))
                            .foregroundColor(Color.chatTextSecondary)

                        Text(trimmedLabel)
                            .font(.chatSemiBold(size: 12))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(hex: selectedColor))
                            .cornerRadius(8)

                        Spacer(minLength: 0)
                    }
                }

                // Action buttons
                HStack(spacing: 16) {
                    // Remove label button (only show if there's a current label)
                    if let currentLabel = currentLabel, !currentLabel.isEmpty {
                        Button(action: {
                            onDone("", nil)
                        }) {
                            Text(ChatStrings.remove.localizedString())
                                .font(.chatMedium(size: 16))
                                .foregroundColor(Color.chatPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.chatPrimary, lineWidth: 1)
                                )
                                .cornerRadius(20)
                        }
                    }

                    // Done button
                    Button(action: {
                        onDone(labelText, selectedColor)
                    }) {
                        Text(ChatStrings.done.localizedString())
                            .font(.chatBold(size: 18))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.chatPrimary, Color.chatPrimaryDark]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(20)
                    }
                    .disabled(trimmedLabel.isEmpty)
                    .opacity(trimmedLabel.isEmpty ? 0.6 : 1.0)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .background(Color.white)
            .cornerRadius(20)
            .padding(.horizontal, 32)
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        }
        .onAppear {
            if let currentLabel = currentLabel, !currentLabel.isEmpty {
                labelText = currentLabel
            }
            if let currentColor = currentColor?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !currentColor.isEmpty {
                selectedColor = currentColor.hasPrefix("#") ? currentColor : "#\(currentColor)"
            }
        }
        .applyRTLEnvironment()
    }

    private func colorDot(_ colorHex: String) -> some View {
        let isSelected = selectedColor.lowercased() == colorHex.lowercased()
        return Button {
            selectedColor = colorHex
        } label: {
            Circle()
                .fill(Color(hex: colorHex))
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.chatTextPrimary : Color(hex: colorHex).opacity(0.35),
                                lineWidth: isSelected ? 2.5 : 1)
                        .padding(-3)
                )
        }
        .buttonStyle(.plain)
    }
}
