import Foundation

/// Stores the member-selected profile photo locally on this iPhone.
/// Photos are not uploaded or shared with the GATIVX account by this store.
struct MemberProfilePhotoStore {
    private let fileManager: FileManager
    private let directoryOverride: URL?
    private let fileName = "member-profile-photo.jpg"

    init(
        fileManager: FileManager = .default,
        directoryOverride: URL? = nil
    ) {
        self.fileManager = fileManager
        self.directoryOverride = directoryOverride
    }

    func load() throws -> Data? {
        let url = try fileURL()
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            throw NSError(
                domain: "GATIVXMemberProfilePhoto",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The saved member photo is empty. The original file was preserved."]
            )
        }
        return data
    }

    func save(_ data: Data) throws {
        guard !data.isEmpty else {
            throw NSError(
                domain: "GATIVXMemberProfilePhoto",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The selected member photo contains no image data."]
            )
        }

        let url = try fileURL()
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)

        let savedData = try Data(contentsOf: url)
        guard savedData == data else {
            throw NSError(
                domain: "GATIVXMemberProfilePhoto",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "The member photo could not be read back and verified."]
            )
        }
    }

    func delete() throws {
        let url = try fileURL()
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
        guard !fileManager.fileExists(atPath: url.path) else {
            throw NSError(
                domain: "GATIVXMemberProfilePhoto",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "The member photo could not be removed."]
            )
        }
    }

    private func fileURL() throws -> URL {
        if let directoryOverride {
            return directoryOverride.appendingPathComponent(fileName, isDirectory: false)
        }

        guard let supportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw NSError(
                domain: "GATIVXMemberProfilePhoto",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "The iPhone Application Support directory is unavailable."]
            )
        }

        return supportDirectory
            .appendingPathComponent("GATIVX", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}
