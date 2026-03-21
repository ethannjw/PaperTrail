// FolderBookmarkService.swift
// Manages a user-selected folder bookmark for saving receipt PDFs.
// Uses security-scoped bookmarks to persist access across app launches.

import Foundation

struct FolderBookmarkService {

    private static let bookmarkKey = "receiptSaveFolderBookmark"

    /// Save a security-scoped bookmark for the selected folder.
    static func saveBookmark(for url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
    }

    /// Resolve the bookmarked folder URL. Returns nil if no folder selected.
    static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            // Re-save bookmark
            try? saveBookmark(for: url)
        }
        return url
    }

    /// Clear the saved bookmark.
    static func clearBookmark() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    /// Check if a folder has been selected.
    static var hasBookmark: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }
}
