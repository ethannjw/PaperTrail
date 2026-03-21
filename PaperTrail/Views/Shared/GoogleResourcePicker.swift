// GoogleResourcePicker.swift
// Lists Google Drive folders or spreadsheets for the user to pick from.

import SwiftUI

// MARK: - Resource Item

struct GoogleResource: Identifiable {
    let id: String
    let name: String
}

// MARK: - Picker View

struct GoogleResourcePickerView: View {

    enum ResourceType {
        case folder
        case spreadsheet
    }

    let type: ResourceType
    let authService: GoogleAuthService
    let onSelect: (GoogleResource) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var resources: [GoogleResource] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""

    private var filtered: [GoogleResource] {
        if searchText.isEmpty { return resources }
        return resources.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading...")
                } else if let error = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await fetchResources() }
                        }
                    }
                    .padding()
                } else if resources.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: type == .folder ? "folder" : "tablecells")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No \(type == .folder ? "folders" : "spreadsheets") found")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List(filtered) { resource in
                        Button {
                            onSelect(resource)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: type == .folder ? "folder.fill" : "tablecells")
                                    .foregroundColor(type == .folder ? .blue : .green)
                                Text(resource.name)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search")
                }
            }
            .navigationTitle(type == .folder ? "Select Folder" : "Select Spreadsheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                if type == .folder {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("None") {
                            onSelect(GoogleResource(id: "", name: ""))
                            dismiss()
                        }
                    }
                }
            }
            .task { await fetchResources() }
        }
    }

    // MARK: - Fetch

    private func fetchResources() async {
        isLoading = true
        errorMessage = nil

        do {
            let token = try await authService.validAccessToken()
            resources = try await fetchFromDrive(token: token)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func fetchFromDrive(token: String) async throws -> [GoogleResource] {
        let mimeType = type == .folder
            ? "application/vnd.google-apps.folder"
            : "application/vnd.google-apps.spreadsheet"

        let query = "mimeType='\(mimeType)' and trashed=false"
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id,name)"),
            URLQueryItem(name: "orderBy", value: "name"),
            URLQueryItem(name: "pageSize", value: "100")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AppError.unknown("Failed to list resources: \(body)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [[String: Any]] ?? []

        return files.compactMap { file in
            guard let id = file["id"] as? String, let name = file["name"] as? String else { return nil }
            return GoogleResource(id: id, name: name)
        }
    }
}
