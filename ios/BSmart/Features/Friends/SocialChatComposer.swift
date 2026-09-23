import SwiftUI
import PhotosUI
import ImageIO

// Draft and keyboard updates are deliberately isolated from the message list.
struct SocialChatComposer: View {
    @Binding var reply: SocialMessage?
    let dismissKeyboard: Int
    let send: (SocialChatDraft) async throws -> Void
    @State private var text = ""
    @State private var attemptID = UUID()
    @State private var photo: PhotosPickerItem?
    @State private var image: PreparedChatPhoto?
    @State private var preparing = false
    @State private var sending = false
    @State private var failure: String?
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !sending && !preparing && text.unicodeScalars.count <= 2000 &&
            (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || image != nil)
    }

    var body: some View {
        VStack(spacing: 8) {
            if let reply {
                HStack(spacing: 12) {
                    SocialReplyPreview(name: reply.sender?.nickname ?? "Reply".bSmartLocalized, text: reply.preview)
                    Button { self.reply = nil } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }.accessibilityLabel("Cancel reply".bSmartLocalized)
                }.accessibilityElement(children: .contain)
                    .accessibilityIdentifier("friends.reply-preview")
            }
            if let image {
                HStack {
                    Image(uiImage: image.preview).resizable().scaledToFill()
                        .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                    Button {
                        self.image = nil; photo = nil; attemptID = UUID()
                    } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                    .accessibilityLabel("Remove photo".bSmartLocalized)
                    Spacer()
                }
            }
            if let failure {
                Text(failure.bSmartLocalized).font(.footnote).foregroundStyle(BSmartColor.bear)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("friends.send-error")
            }
            HStack(alignment: .bottom, spacing: 10) {
                PhotosPicker(selection: $photo, matching: .images) {
                    Group {
                        if preparing { ProgressView() }
                        else { Image(systemName: "plus").font(.system(size: 22, weight: .medium)) }
                    }
                    .frame(width: 44, height: 44)
                    .background(BSmartColor.brand.opacity(0.12), in: Circle())
                }
                .disabled(sending || preparing)
                .accessibilityLabel("Attach photo".bSmartLocalized)
                .accessibilityIdentifier("friends.attach")
                TextField("Write a message".bSmartLocalized, text: $text, axis: .vertical)
                    .font(.body).lineLimit(1...5).focused($focused)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(BSmartColor.recessed, in: RoundedRectangle(cornerRadius: 22))
                    .disabled(sending)
                    .accessibilityIdentifier("friends.composer")
                Button { Task { await submit() } } label: {
                    Group {
                        if sending { ProgressView().tint(BSmartColor.onAccent) }
                        else { Image(systemName: "arrow.up").font(.system(size: 19, weight: .semibold)) }
                    }
                    .foregroundStyle(canSend || sending ? BSmartColor.onAccent : BSmartColor.secondaryText)
                    .frame(width: 44, height: 44)
                    .background(canSend || sending ? BSmartColor.brand : BSmartColor.recessed, in: Circle())
                }
                .disabled(!canSend)
                .accessibilityLabel("Send message".bSmartLocalized)
                .accessibilityIdentifier("friends.send")
            }
            if text.unicodeScalars.count > 2000 {
                Text("Messages can contain up to 2,000 characters.".bSmartLocalized)
                    .font(.footnote).foregroundStyle(BSmartColor.bear)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(BSmartKeyboardInputRegion())
        .background(BSmartColor.ink)
        .overlay(alignment: .top) { Divider().overlay(BSmartColor.softDivider) }
        .onChange(of: text) { _, _ in attemptID = UUID(); failure = nil }
        .onChange(of: dismissKeyboard) { _, _ in focused = false }
        .onChange(of: reply?.id) { _, id in
            attemptID = UUID()
            if id != nil { focused = true }
        }
        .task(id: photo) {
            guard let photo else { return }
            preparing = true
            defer { if !Task.isCancelled { preparing = false } }
            do {
                guard let bytes = try await photo.loadTransferable(type: Data.self), bytes.count <= 20_000_000 else {
                    throw AccountAccessError.invalidResponse
                }
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try PreparedChatPhoto.prepare(bytes)
                }.value
                try Task.checkCancellation()
                image = prepared; attemptID = UUID(); failure = nil
            } catch {
                if !Task.isCancelled { failure = "Could not load this photo. Please choose another image." }
            }
        }
    }

    private func submit() async {
        guard canSend else { return }
        let draft = SocialChatDraft(id: attemptID, text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                    replyToID: reply?.id, imageBase64: image?.base64)
        sending = true; failure = nil
        defer { sending = false }
        do {
            try await send(draft)
            text = ""; image = nil; photo = nil; reply = nil; attemptID = UUID()
        } catch SocialChatError.rateLimited {
            failure = "You are sending messages too quickly. Please try again later."
        } catch SocialChatError.invalidMessage {
            failure = "Message could not be accepted. Check the text or remove the reply and try again."
            attemptID = UUID()
        } catch {
            failure = "Message not sent. Tap send to retry."
        }
    }
}

struct PreparedChatPhoto {
    let base64: String
    let preview: UIImage

    static func prepare(_ data: Data) throws -> Self {
        guard data.count <= 20_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary) else { throw AccountAccessError.invalidResponse }
        let image = UIImage(cgImage: thumbnail)
        guard let jpeg = image.jpegData(compressionQuality: 0.78), jpeg.count <= 2_097_152 else {
            throw AccountAccessError.invalidResponse
        }
        return Self(base64: jpeg.base64EncodedString(), preview: image)
    }
}
