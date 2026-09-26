import Foundation

@MainActor
final class ConfigStore {
    static let shared = ConfigStore()

    private(set) var configuration: AppConfiguration
    var onChange: (() -> Void)?

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("BTT Lite", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = fileURL ?? base.appendingPathComponent("config.json")
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()

        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? decoder.decode(AppConfiguration.self, from: data) {
            self.configuration = decoded
        } else {
            self.configuration = .empty
        }
    }

    func save() throws {
        let data = try encoder.encode(configuration)
        try data.write(to: fileURL, options: [.atomic])
        onChange?()
    }

    func replace(with newConfiguration: AppConfiguration) throws {
        configuration = newConfiguration
        try save()
    }

    func mutate(_ body: (inout AppConfiguration) -> Void) {
        body(&configuration)
        do { try save() }
        catch { NSLog("BTT Lite: failed to save configuration: %@", String(describing: error)) }
    }

    func activeProfile() -> Profile? {
        configuration.activeProfile
    }

    func setActiveProfile(_ id: UUID) {
        mutate { config in
            guard config.profiles.contains(where: { $0.id == id }) else { return }
            config.activeProfileID = id
        }
    }

    func addProfile(named name: String) {
        mutate { config in
            let profile = Profile(name: name.isEmpty ? "New Profile" : name, rules: [])
            config.profiles.append(profile)
            config.activeProfileID = profile.id
        }
    }

    func duplicateActiveProfile() {
        guard let current = configuration.activeProfile else { return }
        mutate { config in
            var copy = current
            copy.id = UUID()
            copy.name += " Copy"
            copy.rules = copy.rules.map { rule in
                var r = rule
                r.id = UUID()
                r.actions = r.actions.map { action in
                    var a = action
                    a.id = UUID()
                    return a
                }
                return r
            }
            config.profiles.append(copy)
            config.activeProfileID = copy.id
        }
    }

    func deleteActiveProfile() {
        mutate { config in
            guard config.profiles.count > 1,
                  let index = config.activeProfileIndex else { return }
            config.profiles.remove(at: index)
            config.activeProfileID = config.profiles[0].id
        }
    }

    func replaceActiveProfile(with profile: Profile) {
        mutate { config in
            guard let index = config.activeProfileIndex else { return }
            config.profiles[index] = profile
        }
    }
}
