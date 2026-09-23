import SwiftUI
import PhotosUI

enum AccountProfileEditorDraft {
    static func submission(_ draft: AccountProfile, onboarding: Bool) -> AccountProfile {
        var value = draft
        value.handle = AccountProfile.normalizedHandle(value.handle)
        if onboarding && value.needsSetup {
            value.username = value.handle
            value.bio = ""
        }
        return value
    }
}

struct ProfileEditorField<Content: View>: View {
    let title: String
    var isFocused = false
    var detail: String? = nil
    var minHeight: CGFloat = 48
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.bSmartLocalized)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BSmartColor.secondaryText)
                Spacer()
                if let detail {
                    Text(detail).font(.caption).monospacedDigit()
                        .foregroundStyle(BSmartColor.tertiaryText)
                }
            }
            content()
                .font(.body)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: minHeight - 24, alignment: .topLeading)
                .padding(12)
                .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isFocused ? BSmartColor.brand : BSmartColor.softDivider,
                                  lineWidth: isFocused ? 1.5 : 0.5))
        }
        .padding(.vertical, 7)
    }
}

struct ProfilePhotoEditor<Avatar: View, Options: View>: View {
    @Binding var photo: PhotosPickerItem?
    var isLoading: Bool
    @ViewBuilder let avatar: () -> Avatar
    @ViewBuilder let options: () -> Options

    var body: some View {
        PhotosPicker(selection: $photo, matching: .images) {
            avatar()
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BSmartColor.primaryText)
                        .frame(width: 30, height: 30)
                        .background(BSmartColor.elevated, in: Circle())
                        .overlay(Circle().strokeBorder(BSmartColor.ink, lineWidth: 3))
                }
                .overlay {
                    if isLoading {
                        Circle().fill(BSmartColor.ink.opacity(0.65))
                        ProgressView().tint(BSmartColor.brand)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change photo".bSmartLocalized)
        .accessibilityIdentifier("profile.photo.change")
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 16)
        .padding(.top, 64)
        .padding(.bottom, 12)
        .background(alignment: .top) {
            RoundedRectangle(cornerRadius: 8)
                .fill(BSmartColor.surface)
                .frame(height: 112)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(BSmartColor.softDivider, lineWidth: 0.5))
        }
        .overlay(alignment: .topTrailing) {
            Menu(content: options) {
                Image(systemName: "ellipsis").font(.body.weight(.semibold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .frame(width: 44, height: 44)
                    .background(BSmartColor.elevated, in: Circle())
            }
            .accessibilityLabel("Photo options".bSmartLocalized)
            .accessibilityIdentifier("profile.photo.options")
        }
    }
}
