import SwiftUI
import PhotosUI
import ImageIO

struct UserProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: LocalUserProfileStore
    private enum Field: Hashable { case name, bio }
    @FocusState private var focusedField: Field?
    @State private var draft: LocalUserProfile
    @State private var photo: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var errorMessage: String?
    private let scope: String

    init(store: LocalUserProfileStore) {
        self.store = store
        scope = store.scope
        _draft = State(initialValue: store.profile)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ProfilePhotoEditor(photo: $photo, isLoading: loadingPhoto) {
                        UserProfileAvatar(data: draft.avatarData, size: 88)
                    } options: {
                        Button(role: .destructive) { photo = nil; draft.avatarData = nil } label: {
                            Label("Remove photo".bSmartLocalized, systemImage: "trash")
                        }.disabled(draft.avatarData == nil)
                            .accessibilityIdentifier("profile.photo.remove")
                    }
                    VStack(spacing: 0) {
                        ProfileEditorField(title: "Nickname", isFocused: focusedField == .name) {
                            TextField("bSmart Investor".bSmartLocalized, text: $draft.nickname)
                                .textContentType(.nickname).submitLabel(.next)
                                .focused($focusedField, equals: .name).onSubmit { focusedField = .bio }
                                .accessibilityIdentifier("profile.edit.nickname")
                                .onChange(of: draft.nickname) { _, value in
                                    if value.count > 28 { draft.nickname = String(value.prefix(28)) }
                                }
                        }
                        ProfileEditorField(title: "Bio", isFocused: focusedField == .bio,
                                           detail: "\(draft.bio.unicodeScalars.count)/120", minHeight: 112) {
                            TextField("Bio".bSmartLocalized, text: $draft.bio, axis: .vertical)
                                .lineLimit(3...5).accessibilityIdentifier("profile.edit.bio")
                                .focused($focusedField, equals: .bio)
                                .onChange(of: draft.bio) { _, value in
                                    if value.count > 120 { draft.bio = String(value.prefix(120)) }
                                }
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage.bSmartLocalized).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                            .accessibilityIdentifier("profile.edit.error")
                    }
                }
                .padding(24)
                .frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .background(BSmartColor.ink)
            .navigationTitle("Edit profile".bSmartLocalized).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".bSmartLocalized) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button("Save".bSmartLocalized) {
                    do {
                        try store.save(draft, expectedScope: scope)
                        dismiss()
                    } catch { errorMessage = "Could not save your profile. Please try again." }
                }
                .buttonStyle(AccountPrimaryButtonStyle())
                .disabled(loadingPhoto).accessibilityIdentifier("profile.save")
                .padding(.horizontal, 24).padding(.vertical, 12)
                .frame(maxWidth: 520).frame(maxWidth: .infinity)
                .background(BSmartColor.ink)
            }
            .task(id: photo) {
                guard let photo else { loadingPhoto = false; return }
                loadingPhoto = true
                errorMessage = nil
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self),
                          data.count <= 20_000_000,
                          let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: 256
                          ] as CFDictionary),
                          let avatar = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.8) else {
                        throw LocalUserProfileStore.ProfileError.photoTooLarge
                    }
                    try Task.checkCancellation()
                    draft.avatarData = avatar
                } catch {
                    guard !Task.isCancelled else { return }
                    errorMessage = "Could not load this photo. Please choose another image."
                }
                loadingPhoto = false
            }
        }.bSmartPage()
    }
}
