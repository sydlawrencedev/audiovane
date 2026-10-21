import Foundation

/// Where the app keeps the user's data on disk.
///
/// One place, so the folder has one name. The app was called AudioVane when
/// this was first written, and the folder was called AUDIOVANE (and, briefly,
/// AudioVane — the same directory on a case-insensitive disk). It is now
/// Vibresia, and the old folder is moved across on first launch so that
/// nobody loses their custom vibescapes, their hamster sprites or their settings.
enum SupportFolder {
    /// The folder: `~/Library/Application Support/Vibresia`.
    static var root: URL {
        base.appendingPathComponent("Vibresia", isDirectory: true)
    }

    /// A subfolder of it — `Hamsters`, `Vibescapes`, `Crashes`.
    static func folder(_ name: String) -> URL {
        root.appendingPathComponent(name, isDirectory: true)
    }

    private static var base: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// The names the folder has been called. On a case-insensitive disk
    /// "AudioVane" and "AUDIOVANE" are the same directory, so only one of
    /// them will ever be there — but both are checked so this works on a
    /// case-sensitive one too.
    private static let legacyNames = ["AUDIOVANE", "AudioVane"]

    /// Moves the old folder to the new name, once.
    ///
    /// Safe to call more than once: it does nothing once the new folder
    /// exists. If both exist, the old one is left alone rather than merged
    /// or overwritten — the new folder is the one the app is using, and
    /// quietly deleting the other's contents would be worse than leaving
    /// it be.
    static func migrateIfNeeded() {
        let fm = FileManager.default
        let new = root
        if !fm.fileExists(atPath: new.path) {
            for legacy in legacyNames {
                let old = base.appendingPathComponent(legacy, isDirectory: true)
                guard fm.fileExists(atPath: old.path) else { continue }
                do {
                    try fm.moveItem(at: old, to: new)
                    NSLog("[MIGRATE] moved Application Support/\(legacy) to Vibresia")
                } catch {
                    // Not fatal: the app will start with an empty folder, and
                    // the old one is still there to be moved by hand.
                    NSLog("[MIGRATE] couldn't move \(legacy): \(error.localizedDescription)")
                }
                return
            }
        }
        migrateSubfolders(of: new)
    }

    /// Renames the folders inside the app's own directory that were renamed
    /// with the terminology.
    ///
    /// The user's own vibescapes live in a folder the app points at, so a
    /// rename that missed this would quietly look like their work had
    /// vanished. The list is applied in order and every step is independent,
    /// so a machine that skipped a release and went straight from the old name
    /// to the newest still ends up in the right place.
    private static func migrateSubfolders(of root: URL) {
        let fm = FileManager.default
        let renames = [("CustomModes", "Vibscapes"), ("Vibscapes", "Vibescapes")]
        for (oldName, newName) in renames {
            let old = root.appendingPathComponent(oldName, isDirectory: true)
            let new = root.appendingPathComponent(newName, isDirectory: true)
            guard fm.fileExists(atPath: old.path) else { continue }
            if fm.fileExists(atPath: new.path) {
                // An empty destination is a leftover, not a conflict — a build
                // that created the new folder before moving anything into it
                // would otherwise wedge the migration forever, and the user's
                // vibescapes would read as deleted. Only an empty one is
                // removed; two populated folders are left for a person to sort.
                let contents = (try? fm.contentsOfDirectory(atPath: new.path)) ?? []
                guard contents.isEmpty else { continue }
                try? fm.removeItem(at: new)
            }
            do {
                try fm.moveItem(at: old, to: new)
                NSLog("[MIGRATE] moved \(oldName) to \(newName)")
            } catch {
                NSLog("[MIGRATE] couldn't move \(oldName): \(error.localizedDescription)")
            }
        }
    }
}
