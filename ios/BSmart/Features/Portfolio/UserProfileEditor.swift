import SwiftUI
import PhotosUI
import ImageIO

struct UserProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: LocalUserProfileStore
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
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 20) {
                        UserProfileAvatar(data: draft.avatarData, size: 88)
                        VStack(alignment: .leading, spacing: 12) {
                            PhotosPicker(selection: $photo, matching: .images) {
                                Label("Change photo".bSmartLocalized, systemImage: "photo")
                            }.accessibilityIdentifier("profile.photo.change")
                            if loadingPhoto { ProgressView() }
                            if draft.avatarData != nil {
                                Button("Remove photo".bSmartLocalized) {
                                    photo = nil
                                    draft.avatarData = nil
                                }.accessibilityIdentifier("profile.photo.remove")
                            }
                        }.font(.subheadline).tint(BSmartColor.brand)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nickname".bSmartLocalized).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                        TextField("bSmart Investor".bSmartLocalized, text: $draft.nickname)
                            .textContentType(.nickname).submitLabel(.done)
                            .accessibilityIdentifier("profile.edit.nickname")
                            .onChange(of: draft.nickname) { _, value in draft.nickname = String(value.prefix(28)) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bio".bSmartLocalized).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                        TextField("Bio".bSmartLocalized, text: $draft.bio, axis: .vertical)
                            .lineLimit(3...5).accessibilityIdentifier("profile.edit.bio")
                            .onChange(of: draft.bio) { _, value in draft.bio = String(value.prefix(120)) }
                    }
                    if let errorMessage {
                        Text(errorMessage.bSmartLocalized).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                            .accessibilityIdentifier("profile.edit.error")
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(24)
            }
            .background(BSmartColor.ink)
            .navigationTitle("Edit profile".bSmartLocalized).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".bSmartLocalized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save".bSmartLocalized) {
                        do {
                            try store.save(draft, expectedScope: scope)
                            dismiss()
                        } catch { errorMessage = "Could not save your profile. Please try again." }
                    }.disabled(loadingPhoto).accessibilityIdentifier("profile.save")
                }
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
