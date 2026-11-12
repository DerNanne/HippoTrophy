import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A photo in a form: what it looks like, and the way to change it or the
/// part its tile shows. Works on whatever the binding holds — the exercise
/// editor's draft, so Cancel leaves the store alone, or a machine itself.
struct PhotoSection: View {
    @Binding var photo: PhotoDraft?
    /// The shape of the tile the photo shows in, which the preview and the
    /// framing take too.
    let aspectRatio: CGFloat

    @State private var preview: UIImage?
    @State private var showLibrary = false
    @State private var showFiles = false
    @State private var showFullPhoto = false
    @State private var showFraming = false
    @State private var picked: PhotosPickerItem?
    @State private var isPreparing = false
    @State private var failure: String?

    var body: some View {
        Section {
            if photo != nil {
                Button {
                    showFullPhoto = true
                } label: {
                    PhotoFrame(image: preview, framing: photo?.framing ?? .centered, aspectRatio: aspectRatio)
                        // A square at full width would fill the screen.
                        .frame(maxHeight: 260)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .accessibilityLabel("Show Photo")
            }
            Menu {
                Button("Photo Library", systemImage: "photo.on.rectangle") { showLibrary = true }
                Button("Files", systemImage: "folder") { showFiles = true }
                if photo != nil {
                    Button("Adjust Framing", systemImage: "crop") { showFraming = true }
                        .disabled(preview == nil)
                    Button("Remove Photo", systemImage: "trash", role: .destructive) { photo = nil }
                }
            } label: {
                HStack {
                    Label(photo == nil ? "Add Photo" : "Change Photo", systemImage: "camera")
                    if isPreparing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isPreparing)
            // All of it on this one row, the one that is always there: in a
            // form, what hangs on a section hangs on each of its rows, and two
            // rows presenting the same sheet close the editor they sit in.
            .photosPicker(isPresented: $showLibrary, selection: $picked, matching: .images, preferredItemEncoding: .current)
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image]) { result in
                pickFile(result)
            }
            .alert("Photo", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
            .task(id: photo?.data) {
                guard let data = photo?.data else {
                    preview = nil
                    return
                }
                preview = await PhotoThumbnails.decode(data, longEdge: PhotoFile.longEdge)
            }
            .onChange(of: picked) { _, item in
                guard let item else { return }
                picked = nil
                Task { await pickFromLibrary(item) }
            }
            .sheet(isPresented: $showFullPhoto) {
                PhotoFullView(image: preview)
            }
            .sheet(isPresented: $showFraming) {
                if let preview, let photo {
                    PhotoFramingView(image: preview, aspectRatio: aspectRatio, framing: photo.framing) { framing in
                        self.photo?.framing = framing
                    }
                }
            }
        } footer: {
            Text("Made smaller to save space. It stays on this iPhone and goes along in a backup with photos.")
        }
    }

    private func pickFromLibrary(_ item: PhotosPickerItem) async {
        isPreparing = true
        defer { isPreparing = false }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            failure = "This picture could not be loaded."
            return
        }
        await prepare(data)
    }

    private func pickFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let canAccess = url.startAccessingSecurityScopedResource()
            defer {
                if canAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            Task { await prepare(data) }
        } catch {
            failure = "This file could not be read: \(error.localizedDescription)"
        }
    }

    private func prepare(_ data: Data) async {
        isPreparing = true
        defer { isPreparing = false }
        let prepared = await Task.detached(priority: .userInitiated) {
            PhotoFile.prepared(from: data)
        }.value
        guard let prepared else {
            failure = "This file is not a picture the app can read."
            return
        }
        // A new picture starts in the middle: the old framing was about
        // another one.
        photo = PhotoDraft(data: prepared)
    }
}

/// The whole photo, uncropped, in the middle of the screen: the bar with Done
/// lies over the black above it rather than pushing the photo down.
private struct PhotoFullView: View {
    let image: UIImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            }
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
