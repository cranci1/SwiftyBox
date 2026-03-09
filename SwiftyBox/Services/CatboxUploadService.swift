//
//  CatboxUploadService.swift
//  SwiftyBox
//
//  Created by Francesco on 02/03/26.
//

import Foundation

final class CatboxUploadService {
    func upload(selection: UploadSelection, options: UploadOptions, onProgress: @escaping @MainActor (Double) -> Void) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = makeMultipartBody(boundary: boundary, selection: selection, options: options)
        
        var request = URLRequest(url: options.target.endpointURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await uploadWithProgress(request: request, body: body, onProgress: onProgress)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadServiceError.invalidResponse
        }
        
        let resultText = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw UploadServiceError.uploadFailed(statusCode: httpResponse.statusCode, message: resultText)
        }
        
        guard resultText.lowercased().hasPrefix("http") else {
            throw UploadServiceError.serviceError(message: resultText)
        }
        
        return resultText
    }
    
    private func uploadWithProgress(request: URLRequest, body: Data, onProgress: @escaping @MainActor (Double) -> Void) async throws -> (Data, URLResponse) {
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
                    continuation.resume(throwing: UploadServiceError.invalidResponse)
                    return
                }
                
                continuation.resume(returning: (data, response))
            }
            
            observation = task.progress.observe(\.fractionCompleted, options: [.new]) { progress, _ in
                let clampedValue = min(max(progress.fractionCompleted, 0), 1)
                Task {
                    await onProgress(clampedValue)
                }
            }
            
            task.resume()
        }
    }
    
    private func makeMultipartBody(boundary: String, selection: UploadSelection, options: UploadOptions) -> Data {
        var body = Data()
        
        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        appendField(name: "reqtype", value: "fileupload")
        
        if options.target == .catbox {
            let cleanUserHash = options.userHash.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanUserHash.isEmpty {
                appendField(name: "userhash", value: cleanUserHash)
            }
        } else {
            appendField(name: "time", value: options.duration.rawValue)
            appendField(name: "fileNameLength", value: String(options.fileNameLength))
        }
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"fileToUpload\"; filename=\"\(selection.filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(selection.data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
}

enum UploadServiceError: LocalizedError {
    case invalidResponse
    case uploadFailed(statusCode: Int, message: String)
    case serviceError(message: String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server."
        case let .uploadFailed(statusCode, message):
            return "Upload failed (\(statusCode)): \(message)"
        case let .serviceError(message):
            return "Service returned an error: \(message)"
        }
    }
}
