//
//  UploadViewModel.swift
//  SwiftyBox
//
//  Created by Francesco on 02/03/26.
//

import Foundation

@MainActor
final class UploadViewModel: ObservableObject {
    @Published var selectedTarget: UploadTarget = .catbox
    @Published var selectedDuration: LitterboxDuration {
        didSet { defaults.set(selectedDuration.rawValue, forKey: Keys.litterboxDuration) }
    }
    @Published var litterboxFileNameLength: Int {
        didSet { defaults.set(litterboxFileNameLength, forKey: Keys.litterboxFileNameLength) }
    }
    @Published var userHash: String {
        didSet { defaults.set(userHash, forKey: Keys.userHash) }
    }
    
    @Published var isUploading = false
    @Published var uploadProgress = 0.0
    @Published var uploadedURL = ""
    @Published var errorMessage = ""
    @Published private(set) var selectedName: String?
    @Published private(set) var selectedSizeLabel: String?
    
    private let defaults: UserDefaults
    private let uploadService: CatboxUploadService
    private var currentSelection: UploadSelection?
    
    private enum Keys {
        static let litterboxDuration = "litterboxDuration"
        static let litterboxFileNameLength = "litterboxFileNameLength"
        static let userHash = "userHash"
    }
    
    init(defaults: UserDefaults = .standard, uploadService: CatboxUploadService = CatboxUploadService()) {
        self.defaults = defaults
        self.uploadService = uploadService
        
        if let rawDuration = defaults.string(forKey: Keys.litterboxDuration),
           let duration = LitterboxDuration(rawValue: rawDuration) {
            selectedDuration = duration
        } else {
            selectedDuration = .oneDay
        }
        
        let persistedNameLength = defaults.integer(forKey: Keys.litterboxFileNameLength)
        litterboxFileNameLength = persistedNameLength == 0 ? 16 : persistedNameLength
        userHash = defaults.string(forKey: Keys.userHash) ?? ""
    }
    
    var isUploadDisabled: Bool {
        isUploading || currentSelection == nil
    }
    
    func selectFile(url: URL) async {
        do {
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            let data = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: url)
            }
                .value
            let selection = UploadSelection(
                data: data,
                filename: url.lastPathComponent,
                sizeInBytes: data.count
            )
            applySelection(selection)
        } catch {
            errorMessage = "Could not read selected file: \(error.localizedDescription)"
        }
    }
    
    func selectMedia(data: Data, filenameExtension: String?) {
        let ext = (filenameExtension?.isEmpty == false) ? filenameExtension! : "dat"
        let selection = UploadSelection(
            data: data,
            filename: "asset-\(Int(Date().timeIntervalSince1970)).\(ext)",
            sizeInBytes: data.count
        )
        applySelection(selection)
    }
    
    func upload() async {
        guard let currentSelection else { return }
        
        isUploading = true
        uploadProgress = 0
        uploadedURL = ""
        errorMessage = ""
        
        defer {
            isUploading = false
            uploadProgress = 0
        }
        
        do {
            let options = UploadOptions(
                target: selectedTarget,
                duration: selectedDuration,
                fileNameLength: litterboxFileNameLength,
                userHash: userHash
            )
            
            let url = try await uploadService.upload(selection: currentSelection, options: options) { [weak self] progress in
                self?.uploadProgress = progress
            }
            
            uploadedURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func applySelection(_ selection: UploadSelection) {
        currentSelection = selection
        selectedName = selection.filename
        selectedSizeLabel = byteCountLabel(for: selection.sizeInBytes)
        uploadedURL = ""
        errorMessage = ""
    }
    
    private func byteCountLabel(for bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
