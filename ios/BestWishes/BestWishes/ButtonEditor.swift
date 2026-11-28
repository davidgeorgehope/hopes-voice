import PhotosUI
import SwiftUI
import UIKit

enum ButtonImageChoice: Equatable {
    case keep
    case generate
    case photo(UIImage)
}

/// Caregiver draft for a new or existing board button. Saved in one shot from the sheet.
struct ButtonEditorDraft: Equatable, Identifiable {
    var id: String { existingID ?? "new-\(coord.row)-\(coord.col)" }

    var existingID: String?
    var coord: GridCoord
    var kind: ButtonKind
    var label: String
    var speak: String
    var backgroundHex: String
    var borderHex: String
    var imageChoice: ButtonImageChoice
    var currentImage: UIImage?
    /// For a folder button, the board to open. Nil means create a new folder named `label`.
    var folderLinkID: String?

    var isNew: Bool { existingID == nil }

    var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedSpeak: String {
        let speak = speak.trimmingCharacters(in: .whitespacesAndNewlines)
        return speak.isEmpty ? trimmedLabel : speak
    }

    var canSave: Bool { !trimmedLabel.isEmpty }

    static func blank(at coord: GridCoord) -> ButtonEditorDraft {
        ButtonEditorDraft(
            existingID: nil,
            coord: coord,
            kind: .word,
            label: "",
            speak: "",
            backgroundHex: CellStyle.default.backgroundHex,
            borderHex: CellStyle.default.borderHex,
            imageChoice: .generate,
            currentImage: nil,
            folderLinkID: nil
        )
    }
}

struct ButtonEditorSheet: View {
    @Binding var draft: ButtonEditorDraft
    var availableFolders: [(id: String, name: String)] = []
    var isBusy: Bool = false
    var errorMessage: String? = nil
    var onSave: () -> Void
    var onCancel: () -> Void
    var onHide: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var photoItem: PhotosPickerItem?
    @Environment(\.boardChrome) private var chrome

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    typePicker
                    field("Label", text: $draft.label, identifier: "editorLabel")
                        .onChange(of: draft.label) { oldValue, newValue in
                            if draft.speak.isEmpty || draft.speak == oldValue {
                                draft.speak = newValue
                            }
                        }
                    field("Spoken text", text: $draft.speak, identifier: "editorSpeak", prompt: "Defaults to the label")
                    pictureSection
                    colorSection
                    if draft.kind == .folder, !availableFolders.isEmpty {
                        folderLinkSection
                    }
                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.coral)
                            .accessibilityIdentifier("editorError")
                    }
                    if !draft.isNew {
                        editorDangerActions
                    }
                }
                .padding(20)
            }
            .background(Theme.board.ignoresSafeArea())
            .navigationTitle(draft.isNew ? "Add button" : "Edit button")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier("editorCancel")
                        .disabled(isBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isBusy ? "Saving…" : "Save", action: onSave)
                        .disabled(!draft.canSave || isBusy)
                        .accessibilityIdentifier("editorSave")
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    draft.imageChoice = .photo(image)
                    draft.currentImage = image
                }
            }
        }
    }

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Button type")
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.muted)
            Picker("Button type", selection: $draft.kind) {
                Text("Word").tag(ButtonKind.word)
                Text("Folder").tag(ButtonKind.folder)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("editorKind")
            .disabled(!draft.isNew)
        }
    }

    private func field(_ title: String, text: Binding<String>, identifier: String, prompt: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.muted)
            TextField(prompt ?? title, text: text)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .padding(12)
                .background(Theme.cream)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityIdentifier(identifier)
        }
    }

    private var pictureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Picture")
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.muted)
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: draft.backgroundHex) ?? Theme.cream)
                    .frame(height: 160)
                if let image = draft.currentImage, !(draft.imageChoice == .generate && draft.existingID != nil) {
                    Image(uiImage: PecsImage.fillingSubject(image))
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                        .frame(height: 160)
                } else if draft.imageChoice == .generate {
                    VStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 28, weight: .bold))
                        Text(draft.existingID == nil ? "AI picture on save" : "New AI picture on save")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    }
                    .foregroundStyle(Theme.muted)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(Theme.muted)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(hex: draft.borderHex) ?? Theme.cardStroke, lineWidth: 4)
            )
            HStack(spacing: 10) {
                Button {
                    draft.imageChoice = .generate
                } label: {
                    chipLabel(draft.existingID == nil ? "Generate" : "New picture", selected: draft.imageChoice == .generate)
                }
                .accessibilityIdentifier("editorGenerate")
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    chipLabel("Choose photo", selected: {
                        if case .photo = draft.imageChoice { return true }
                        return false
                    }())
                }
                .accessibilityIdentifier("editorChoosePhoto")
                if !draft.isNew {
                    Button {
                        draft.imageChoice = .keep
                    } label: {
                        chipLabel("Keep", selected: draft.imageChoice == .keep)
                    }
                    .accessibilityIdentifier("editorKeepPicture")
                }
            }
            Text("Photos stay on this device and are never uploaded.")
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(Theme.muted)
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Colors")
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.muted)
            colorRow("Background", hex: $draft.backgroundHex, identifier: "editorBackground")
            colorRow("Border", hex: $draft.borderHex, identifier: "editorBorder")
        }
    }

    private func colorRow(_ title: String, hex: Binding<String>, identifier: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 110, alignment: .leading)
            ForEach(Self.palette, id: \.self) { swatch in
                Button {
                    hex.wrappedValue = swatch
                } label: {
                    Circle()
                        .fill(Color(hex: swatch) ?? .gray)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle().stroke(Theme.ink.opacity(hex.wrappedValue == swatch ? 0.9 : 0.2), lineWidth: hex.wrappedValue == swatch ? 3 : 1)
                        )
                }
                .accessibilityLabel("\(title) \(swatch)")
                .accessibilityIdentifier("\(identifier)-\(swatch)")
            }
        }
    }

    private var folderLinkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Opens folder")
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.muted)
            Picker("Folder link", selection: Binding(
                get: { draft.folderLinkID ?? "" },
                set: { draft.folderLinkID = $0.isEmpty ? nil : $0 }
            )) {
                Text("New folder named like the label").tag("")
                ForEach(availableFolders, id: \.id) { folder in
                    Text(folder.name).tag(folder.id)
                }
            }
            .accessibilityIdentifier("editorFolderLink")
        }
    }

    private var editorDangerActions: some View {
        HStack(spacing: 12) {
            if onHide != nil, draft.kind == .word {
                Button("Hide", action: { onHide?() })
                    .font(.system(.body, design: .rounded).weight(.heavy))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(Theme.cream)
                    .background(Theme.slate)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("editorHide")
            }
            if onDelete != nil {
                Button("Delete", role: .destructive, action: { onDelete?() })
                    .font(.system(.body, design: .rounded).weight(.heavy))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(Theme.cream)
                    .background(Theme.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("editorDelete")
            }
        }
        .padding(.top, 8)
    }

    private func chipLabel(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Theme.cream : Theme.ink)
            .background(selected ? Theme.slate : Theme.cream)
            .clipShape(Capsule())
    }

    /// Original swatches, not copied from any commercial AAC palette.
    static let palette = ["FCFCF7", "93C47D", "6FA8DC", "FFD966", "F4CCCC", "E8D5B7", "1C1A17"]
}
