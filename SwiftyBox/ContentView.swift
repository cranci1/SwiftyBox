//
//  ContentView.swift
//  SwiftyBox
//
//  Created by Francesco on 01/03/26.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

enum UploadTarget: String, CaseIterable, Identifiable {
    case catbox = "Catbox"
    case litterbox = "Litterbox"
    
    var id: Self { self }
    
    var endpointURL: URL {
        switch self {
        case .catbox:
            return URL(string: "https://catbox.moe/user/api.php")!
        case .litterbox:
            return URL(string: "https://litterbox.catbox.moe/resources/internals/api.php")!
        }
    }
}

enum LitterboxDuration: String, CaseIterable, Identifiable {
    case oneHour = "1h"
    case twelveHours = "12h"
    case oneDay = "24h"
    case threeDays = "72h"
    
    var id: Self { self }
    
    var label: String {
        switch self {
        case .oneHour:
            return "1 hour"
        case .twelveHours:
            return "12 hours"
        case .oneDay:
            return "24 hours"
        case .threeDays:
            return "72 hours"
        }
    }
}

struct ContentView: View {
    @State private var isFileImporterPresented = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedFileURL: URL?
    @State private var selectedUploadData: Data?
    @State private var selectedUploadFilename: String?
    @State private var selectedTarget: UploadTarget = .catbox
    @State private var selectedDuration: LitterboxDuration = .oneDay
    @State private var litterboxFileNameLength = 16
    @State private var userHash = ""
    @State private var isUploading = false
    @State private var uploadProgress = 0.0
    @State private var uploadedURL = ""
    @State private var errorMessage = ""
    
    init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "litterboxDuration"),
           let dur = LitterboxDuration(rawValue: raw) {
            _selectedDuration = State(initialValue: dur)
        }
        let length = defaults.integer(forKey: "litterboxFileNameLength")
        if length != 0 {
            _litterboxFileNameLength = State(initialValue: length)
        }
        if let hash = defaults.string(forKey: "userHash") {
            _userHash = State(initialValue: hash)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                headerSection
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
                
                Form {
                    Section(header: Text("Destination")) { destinationSection }
                    Section(header: Text("Options"))     { optionsSection }
                    Section(header: Text("Source"))      { fileSection }
                    Section {
                        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
                            uploadButton
                                .glassEffect()
                        } else {
                            uploadButton
                        }
                    }
                    .listRowBackground(Color.accentColor.opacity(0.3))
                    
                    if isUploading { Section { uploadProgressSection } }
                    if !uploadedURL.isEmpty {
                        Section(header: Text("Uploaded URL")) {
                            resultSection
                        }
                    }
                    if !errorMessage.isEmpty {
                        Section {
                            errorSection
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let files):
                selectedFileURL = files.first
                uploadedURL = ""
                selectedUploadData = nil
                selectedUploadFilename = nil
                selectedPhotoItem = nil
                errorMessage = ""
            case .failure(let error):
                errorMessage = "Could not select file: \(error.localizedDescription)"
            }
        }
        .onChange(of: selectedPhotoItem) { newItem in
            Task {
                await loadSelectedPhoto(from: newItem)
            }
        }
        .onChange(of: selectedDuration) { newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: "litterboxDuration")
        }
        .onChange(of: litterboxFileNameLength) { newValue in
            UserDefaults.standard.set(newValue, forKey: "litterboxFileNameLength")
        }
        .onChange(of: userHash) { newValue in
            UserDefaults.standard.set(newValue, forKey: "userHash")
        }
    }
    
    private var headerSection: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .font(.title.bold())
                .foregroundColor(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("SwiftyBox")
                    .font(.title.bold())
                    .foregroundColor(Color.accentColor)
                Text("Upload files and photos to Catbox or Litterbox")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
    }
    
    private var selectedDisplayName: String? {
        if let selectedFileURL {
            return selectedFileURL.lastPathComponent
        }
        return selectedUploadFilename
    }
    
    private var selectedDisplaySize: String? {
        if let selectedFileURL {
            return fileSizeLabel(for: selectedFileURL)
        }
        if let selectedUploadData {
            return byteCountLabel(for: selectedUploadData.count)
        }
        return nil
    }
    
    private var isUploadDisabled: Bool {
        if isUploading { return true }
        let hasSelection = selectedFileURL != nil || (selectedUploadData != nil && selectedUploadFilename != nil)
        return !hasSelection
    }
    
    private func resetMessages() {
        uploadedURL = ""
        errorMessage = ""
    }
    
    private func byteCountLabel(for bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    @MainActor
    private func loadSelectedPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Could not load selected item."
                return
            }
            
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "dat"
            selectedUploadData = data
            selectedUploadFilename = "asset-\(Int(Date().timeIntervalSince1970)).\(ext)"
            selectedFileURL = nil
            resetMessages()
        } catch {
            errorMessage = "Could not load selected item: \(error.localizedDescription)"
        }
    }
    
    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Destination", selection: $selectedTarget) {
                ForEach(UploadTarget.allCases) { target in
                    Text(target.rawValue).tag(target)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    @ViewBuilder
    private var optionsSection: some View {
        if selectedTarget == .catbox {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Optional userhash", text: $userHash)
                    .textFieldStyle(.roundedBorder)
            }
        } else {
            VStack(alignment: .leading) {
                Picker("Duration", selection: $selectedDuration) {
                    ForEach(LitterboxDuration.allCases) { duration in
                        Text(duration.label).tag(duration)
                    }
                }
                .pickerStyle(.menu)
                
                HStack {
                    Text("Name length")
                    Spacer()
                    Picker("Filename length", selection: $litterboxFileNameLength) {
                        Text("6 characters").tag(6)
                        Text("16 characters").tag(16)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
        }
    }
    
    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("Choose File", systemImage: "doc")
                }
                
                Spacer()
                
                PhotosPicker(selection: $selectedPhotoItem, matching: .any(of: [.images, .videos]), photoLibrary: .shared()) {
                    Label("Choose Media", systemImage: "photo")
                }
            }
            
            if let selectedDisplayName {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDisplayName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let selectedDisplaySize {
                        Text(selectedDisplaySize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            } else {
                Text("No file selected")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var uploadButton: some View {
        Button {
            guard !isUploadDisabled else { return }
            Task {
                await uploadSelectedFile()
            }
        } label: {
            HStack(alignment: .center) {
                Image(systemName: isUploading ? "arrow.triangle.2.circlepath" : "icloud.and.arrow.up.fill")
                Text(isUploading ? "Uploading…" : "Upload")
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .disabled(isUploadDisabled)
        .opacity(isUploadDisabled ? 0.6 : 1)
        .allowsHitTesting(!isUploadDisabled)
    }
    
    @ViewBuilder
    private var uploadProgressSection: some View {
        if isUploading {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: uploadProgress, total: 1.0)
                    .progressViewStyle(.linear)
                Text("\(Int(uploadProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }
    
    @ViewBuilder
    private var resultSection: some View {
        if !uploadedURL.isEmpty {
            if let url = URL(string: uploadedURL) {
                Link(uploadedURL, destination: url)
                    .textSelection(.enabled)
            } else {
                Text(uploadedURL)
                    .textSelection(.enabled)
            }
        }
    }
    
    @ViewBuilder
    private var errorSection: some View {
        if !errorMessage.isEmpty {
            Text(errorMessage)
                .foregroundStyle(.red)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    @MainActor
    private func uploadSelectedFile() async {
        guard selectedFileURL != nil || (selectedUploadData != nil && selectedUploadFilename != nil) else { return }
        
        isUploading = true
        uploadProgress = 0
        uploadedURL = ""
        errorMessage = ""
        
        defer {
            isUploading = false
            uploadProgress = 0
        }
        
        do {
            let fileData: Data
            if let selectedUploadData {
                fileData = selectedUploadData
            } else if let selectedFileURL {
                let hasSecurityScope = selectedFileURL.startAccessingSecurityScopedResource()
                defer {
                    if hasSecurityScope {
                        selectedFileURL.stopAccessingSecurityScopedResource()
                    }
                }
                fileData = try Data(contentsOf: selectedFileURL)
            } else {
                return
            }
            
            let boundary = "Boundary-\(UUID().uuidString)"
            let requestBody = makeMultipartBody(
                boundary: boundary,
                fileData: fileData,
                filename: selectedDisplayName ?? "upload.bin"
            )
            
            var request = URLRequest(url: selectedTarget.endpointURL)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            let (data, response) = try await uploadWithProgress(request: request, body: requestBody)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Invalid response from server."
                return
            }
            
            let resultText = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard (200..<300).contains(httpResponse.statusCode) else {
                errorMessage = "Upload failed (\(httpResponse.statusCode)): \(resultText)"
                return
            }
            
            guard resultText.lowercased().hasPrefix("http") else {
                errorMessage = "Service returned an error: \(resultText)"
                return
            }
            
            uploadedURL = resultText
        } catch {
            errorMessage = "Upload failed: \(error.localizedDescription)"
        }
    }
    
    private func uploadWithProgress(request: URLRequest, body: Data) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            var observation: NSKeyValueObservation?
            
            let task = URLSession.shared.uploadTask(with: request, from: body) { data, response, error in
                observation?.invalidate()
                observation = nil
                
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let data, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                
                continuation.resume(returning: (data, response))
            }
            
            observation = task.progress.observe(\.fractionCompleted, options: [.new]) { progress, _ in
                let fraction = progress.fractionCompleted
                Task { @MainActor in
                    uploadProgress = min(max(fraction, 0), 1)
                }
            }
            
            task.resume()
        }
    }
    
    private func makeMultipartBody(boundary: String, fileData: Data, filename: String) -> Data {
        var body = Data()
        
        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        appendField(name: "reqtype", value: "fileupload")
        
        if selectedTarget == .catbox {
            let cleanUserHash = userHash.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanUserHash.isEmpty {
                appendField(name: "userhash", value: cleanUserHash)
            }
        } else {
            appendField(name: "time", value: selectedDuration.rawValue)
            appendField(name: "fileNameLength", value: String(litterboxFileNameLength))
        }
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"fileToUpload\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
    
    private func fileSizeLabel(for fileURL: URL) -> String {
        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = values?.fileSize ?? 0
        return byteCountLabel(for: fileSize)
    }
}
