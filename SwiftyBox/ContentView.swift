//
//  ContentView.swift
//  SwiftyBox
//
//  Created by Francesco on 01/03/26.
//

import Drops
import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var viewModel = UploadViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    
    @State private var isFileImporterPresented = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Destination") {
                    Picker("Destination", selection: $viewModel.selectedTarget) {
                        ForEach(UploadTarget.allCases) { target in
                            Text(target.rawValue).tag(target)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section("Options") {
                    if viewModel.selectedTarget == .catbox {
                        TextField("Optional userhash", text: $viewModel.userHash)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        Picker("Duration", selection: $viewModel.selectedDuration) {
                            ForEach(LitterboxDuration.allCases) { duration in
                                Text(duration.label).tag(duration)
                            }
                        }
                        
                        Picker("Name length", selection: $viewModel.litterboxFileNameLength) {
                            Text("6 characters").tag(6)
                            Text("16 characters").tag(16)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                
                Section("Source") {
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Label("Choose File", systemImage: "doc")
                    }
                    
                    PhotosPicker(selection: $selectedPhotoItem, matching: .any(of: [.images, .videos]), photoLibrary: .shared()) {
                        Label("Choose Media", systemImage: "photo.on.rectangle")
                    }
                    
                    if let selectedName = viewModel.selectedName {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let size = viewModel.selectedSizeLabel {
                                Text(size)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("No source selected")
                            .foregroundStyle(.secondary)
                    }
                }
                
                if viewModel.isUploading {
                    Section("Progress") {
                        HStack {
                            ProgressView(value: viewModel.uploadProgress, total: 1.0)
                            Text("\(Int(viewModel.uploadProgress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if !viewModel.uploadedURL.isEmpty {
                    Section(header: Text("Uploaded URL"), footer: Text("Hold to copy the link!")) {
                        if let url = URL(string: viewModel.uploadedURL) {
                            Link(viewModel.uploadedURL, destination: url)
                                .onLongPressGesture {
                                    copyUploadedURL()
                                }
                        } else {
                            Text(viewModel.uploadedURL)
                                .onLongPressGesture {
                                    copyUploadedURL()
                                }
                        }
                    }
                }
                
                if !viewModel.errorMessage.isEmpty {
                    Section {
                        Label(viewModel.errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("SwiftyBox")
            .safeAreaInset(edge: .bottom) {
                VStack {
                    Button {
                        Task {
                            await viewModel.upload()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if viewModel.isUploading {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(viewModel.isUploading ? "Uploading…" : "Upload")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Capsule())
                    .disabled(viewModel.isUploadDisabled)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                Task {
                    await viewModel.selectFile(url: url)
                }
                selectedPhotoItem = nil
            case let .failure(error):
                viewModel.errorMessage = "Could not select file: \(error.localizedDescription)"
            }
        }
        .onChange(of: selectedPhotoItem) { newValue in
            guard let item = newValue else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        viewModel.errorMessage = "Could not load selected media."
                        return
                    }
                    let ext = item.supportedContentTypes.first?.preferredFilenameExtension
                    viewModel.selectMedia(data: data, filenameExtension: ext)
                } catch {
                    viewModel.errorMessage = "Could not load selected media: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func copyUploadedURL() {
        UIPasteboard.general.string = viewModel.uploadedURL
        Drops.show(
            Drop(
                title: "Copied",
                subtitle: "to clipboard",
                icon: UIImage(systemName: "checkmark.circle.fill"),
                duration: .seconds(1.75)
            )
        )
    }
}
