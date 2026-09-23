import SwiftUI
import PhotosUI
import ImageIO

struct AccountProfileEditorPage: View {
    @EnvironmentObject private var account: AccountAccessStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = AccountProfileStore()
    let accountID: UUID

    var body: some View {
        Group {
            if account.identity?.id == accountID, let profile = store.profile, store.accountID == accountID {
                AccountProfileEditor(profile: profile, accountID: accountID)
            } else {
                NavigationStack {
                    VStack(spacing: 16) {
                        if store.failed {
                            Text("Profile is unavailable. Please try again.".bSmartLocalized)
                            Button("Retry".bSmartLocalized) { Task { await store.load(account: account) } }
                        } else { ProgressView() }
                    }
                    .navigationTitle("Edit profile".bSmartLocalized)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel".bSmartLocalized) { dismiss() } } }
                }.bSmartPage()
            }
        }
        .task { if account.identity?.id == accountID { await store.load(account: account) } }
        .onChange(of: account.identity?.id) { _, value in if value != accountID { store.clear(); dismiss() } }
    }
}

struct AccountProfileEditor: View {
    @EnvironmentObject private var account: AccountAccessStore
    @Environment(\.dismiss) private var dismiss
    private enum Field: Hashable { case name, handle, bio }
    @FocusState private var focusedField: Field?
    @State private var draft: AccountProfile
    @State private var photo: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var avatar = AccountProfileAvatarInput.keep
    @State private var loadingPhoto = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var needsReload = false
    @State private var legacy: LocalUserProfile?
    let accountID: UUID
    var onboarding = false
    var onSaved: ((AccountProfile) -> Void)?

    init(profile: AccountProfile, accountID: UUID, onboarding: Bool = false,
         onSaved: ((AccountProfile) -> Void)? = nil) {
        var draft = profile
        if onboarding && profile.needsSetup { draft.handle = "" }
        _draft = State(initialValue: draft)
        self.accountID = accountID
        self.onboarding = onboarding; self.onSaved = onSaved
    }

    private var submission: AccountProfile {
        AccountProfileEditorDraft.submission(draft, onboarding: onboarding)
    }

    private var valid: Bool {
        submission.isValid && !busy && !loadingPhoto && !needsReload && account.identity?.id == accountID
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: onboarding ? 32 : 12) {
                    if onboarding {
                        Text("Choose your username".bSmartLocalized)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(BSmartColor.primaryText)
                            .padding(.top, 24)
                        setupPhotoSection
                    } else {
                        photoSection
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ProfileEditorField(title: "Username", isFocused: focusedField == .handle) {
                            HStack(spacing: 6) {
                                Text("@").foregroundStyle(BSmartColor.secondaryText)
                                TextField("Username".bSmartLocalized, text: $draft.handle)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .keyboardType(.asciiCapable).accessibilityIdentifier("profile.edit.handle")
                                    .focused($focusedField, equals: .handle)
                                    .submitLabel(onboarding ? .done : .next)
                                    .onSubmit {
                                        if onboarding { focusedField = nil }
                                        else { focusedField = .name }
                                    }
                            }
                        }
                        if !draft.handle.isEmpty && !AccountProfile.validHandle(AccountProfile.normalizedHandle(draft.handle)) {
                            Text("Use 3-24 letters, numbers or underscores, starting with a letter.".bSmartLocalized)
                                .font(.caption).foregroundStyle(BSmartColor.bear)
                        }
                        if !onboarding {
                            ProfileEditorField(title: "Display name", isFocused: focusedField == .name) {
                                TextField("Display name".bSmartLocalized, text: $draft.username)
                                    .textContentType(.nickname).accessibilityIdentifier("profile.edit.nickname")
                                    .focused($focusedField, equals: .name)
                                    .submitLabel(.next).onSubmit { focusedField = .bio }
                                    .onChange(of: draft.username) { _, value in
                                        if value.unicodeScalars.count > 28 {
                                            draft.username = String(String.UnicodeScalarView(value.unicodeScalars.prefix(28)))
                                        }
                                    }
                            }
                            ProfileEditorField(title: "Bio", isFocused: focusedField == .bio,
                                               detail: "\(draft.bio.unicodeScalars.count)/120", minHeight: 112) {
                                TextField("Bio".bSmartLocalized, text: $draft.bio, axis: .vertical)
                                    .lineLimit(3...5).accessibilityIdentifier("profile.edit.bio")
                                    .focused($focusedField, equals: .bio)
                                    .onChange(of: draft.bio) { _, value in
                                        if value.unicodeScalars.count > 120 {
                                            draft.bio = String(String.UnicodeScalarView(value.unicodeScalars.prefix(120)))
                                        }
                                    }
                            }
                        }
                    }
                    if let legacy {
                        Button("Use profile saved on this device".bSmartLocalized) {
                            draft.username = legacy.nickname.isEmpty ? draft.username : legacy.nickname
                            draft.bio = legacy.bio
                            if let data = legacy.avatarData { photoData = data; avatar = .upload(data) }
                            self.legacy = nil
                        }.font(.subheadline).frame(minHeight: 44)
                    }
                    if let errorMessage {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(errorMessage).foregroundStyle(BSmartColor.bear).accessibilityIdentifier("profile.edit.error")
                            Button("Reload profile".bSmartLocalized) { Task { await reload() } }
                        }.font(.subheadline)
                    }
                }
                .padding(24)
                .frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(BSmartColor.ink)
            .disabled(busy || account.identity?.id != accountID)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle((onboarding ? "Set up your profile" : "Edit profile").bSmartLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button((onboarding ? "Sign out" : "Cancel").bSmartLocalized) {
                        if onboarding { Task { await account.signOut() } } else { dismiss() }
                    }.disabled(busy)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button { Task { await save() } } label: {
                    HStack(spacing: 10) {
                        if busy { ProgressView().tint(BSmartColor.onAccent) }
                        Text((onboarding ? "Continue" : "Save").bSmartLocalized)
                    }
                }
                .buttonStyle(AccountPrimaryButtonStyle())
                .disabled(!valid).accessibilityIdentifier("profile.save")
                .padding(.horizontal, 24).padding(.vertical, 12)
                .frame(maxWidth: 520).frame(maxWidth: .infinity)
                .background(BSmartColor.ink)
            }
            .interactiveDismissDisabled(onboarding || busy)
            .task {
                let local = LocalUserProfileStore()
                local.load(accountID: accountID)
                if !onboarding && account.identity?.id == accountID && local.profile != LocalUserProfile() { legacy = local.profile }
            }
            .task(id: photo) { await loadPhoto() }
        }.bSmartPage()
    }

    private var setupPhotoSection: some View {
        HStack(spacing: 16) {
            PhotosPicker(selection: $photo, matching: .images) {
                HStack(spacing: 16) {
                    Group {
                        if let photoData { UserProfileAvatar(data: photoData, size: 64) }
                        else {
                            BSmartAvatar(url: avatar.action == "remove" ? nil : draft.avatarURL,
                                         name: submission.username, size: 64)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(BSmartColor.onAccent)
                            .frame(width: 26, height: 26)
                            .background(BSmartColor.brand, in: Circle())
                            .overlay(Circle().strokeBorder(BSmartColor.ink, lineWidth: 2))
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text((photoData != nil || (draft.avatarURL != nil && avatar.action != "remove") ? "Change photo" : "Add photo").bSmartLocalized)
                            .font(.body.weight(.medium)).foregroundStyle(BSmartColor.primaryText)
                        Text("Optional".bSmartLocalized)
                            .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    }
                    if loadingPhoto { ProgressView() }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.photo.change")
            Spacer(minLength: 0)
            if photoData != nil || (draft.avatarURL != nil && avatar.action != "remove") {
                Button {
                    photo = nil; photoData = nil; avatar = .remove
                } label: {
                    Image(systemName: "xmark").font(.body)
                        .foregroundStyle(BSmartColor.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Remove photo".bSmartLocalized)
                .accessibilityIdentifier("profile.photo.remove")
            }
        }
    }

    private var photoSection: some View {
        VStack(spacing: 0) {
            ProfilePhotoEditor(photo: $photo, isLoading: loadingPhoto) {
                if let photoData { UserProfileAvatar(data: photoData, size: 88) }
                else {
                    BSmartAvatar(url: avatar.action == "remove" ? nil : draft.avatarURL,
                                 name: draft.username, size: 88)
                }
            } options: {
                Button {
                    photo = nil; photoData = nil; avatar = .provider
                } label: {
                    Label("Use my Google avatar".bSmartLocalized, systemImage: "person.crop.circle")
                }
                Button(role: .destructive) {
                    photo = nil; photoData = nil; avatar = .remove
                } label: {
                    Label("Remove photo".bSmartLocalized, systemImage: "trash")
                }.accessibilityIdentifier("profile.photo.remove")
            }
            if avatar.action == "provider" {
                Label("Google photo selected".bSmartLocalized, systemImage: "checkmark")
                    .font(.caption).foregroundStyle(BSmartColor.brand)
            }
        }
    }

    private func save() async {
        guard valid else { return }
        busy = true; errorMessage = nil
        let sessionRevision = account.walletSessionRevision
        defer { busy = false }
        do {
            let saved = try await NativeAccountProfileClient(account: account).save(submission, avatar: avatar, accountID: accountID)
            guard account.identity?.id == accountID, account.walletSessionRevision == sessionRevision else { return }
            onSaved?(saved)
            dismiss()
        } catch {
            guard account.identity?.id == accountID else { return }
            needsReload = (error as? AccountProfileError) == .conflict
            errorMessage = (error as? AccountProfileError)?.errorDescription
                ?? "Could not save your profile. Please try again.".bSmartLocalized
        }
    }

    private func reload() async {
        busy = true
        defer { busy = false }
        do {
            let value = try await NativeAccountProfileClient(account: account).load(accountID: accountID)
            guard account.identity?.id == accountID, !Task.isCancelled else { return }
            draft = value; photo = nil; photoData = nil; avatar = .keep; needsReload = false; errorMessage = nil
        } catch { errorMessage = "Profile is unavailable. Please try again.".bSmartLocalized }
    }

    private func loadPhoto() async {
        guard let photo else { loadingPhoto = false; return }
        loadingPhoto = true
        do {
            guard let data = try await photo.loadTransferable(type: Data.self), data.count <= 20_000_000,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 256
                  ] as CFDictionary),
                  let data = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.8), data.count <= 200_000 else {
                throw AccountProfileError.invalid
            }
            guard !Task.isCancelled, account.identity?.id == accountID else { return }
            photoData = data; avatar = .upload(data)
        } catch {
            guard !Task.isCancelled, account.identity?.id == accountID else { return }
            errorMessage = "Could not load this photo. Please choose another image.".bSmartLocalized
        }
        loadingPhoto = false
    }
}
