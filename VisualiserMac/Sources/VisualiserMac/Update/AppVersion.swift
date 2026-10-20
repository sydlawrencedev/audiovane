import Foundation

/// A build version, and how to compare two of them.
///
/// Versions are dates: `MAJOR.MINOR.PATCH`, where MAJOR counts years since
/// 2026, MINOR is the month, and PATCH is the day of the month followed by
/// the build number of that day — `0.10.201` is the 20th of October 2026,
/// first build.
///
/// Comparing those as plain numbers doesn't work, because the patch is two
/// things run together. The 20th's tenth build is `2010`, and the 21st's
/// first is `211` — so `2010 > 211`, and a plain numeric sort would call
/// the earlier build the newer one. The patch is split back into its day
/// and build before comparing, which puts them back in the right order.
struct AppVersion {
    let major: Int
    let month: Int
    let day: Int
    let build: Int
    /// Set for versions from before the date scheme, which counted releases
    /// rather than days.
    let legacyPatch: Int?

    init?(_ string: String) {
        let parts = string.split(separator: ".").map(String.init)
        guard parts.count >= 3,
              let major = Int(parts[0]), let month = Int(parts[1]) else { return nil }
        self.major = major
        self.month = month
        let patch = parts[2]
        // A date patch is a two-digit day followed by the build number.
        if patch.count >= 3,
           let day = Int(patch.prefix(2)), (1...31).contains(day),
           let build = Int(patch.dropFirst(2)) {
            self.day = day
            self.build = build
            self.legacyPatch = nil
        } else {
            self.day = 0
            self.build = 0
            self.legacyPatch = Int(patch) ?? 0
        }
    }

    /// True when this version is newer than the other.
    func isNewer(than other: AppVersion) -> Bool {
        // The scheme changed once. Everything built before the change is
        // older than everything built after it, whatever the numbers say.
        if (legacyPatch == nil) != (other.legacyPatch == nil) {
            return legacyPatch == nil
        }
        if let patch = legacyPatch, let otherPatch = other.legacyPatch {
            // Two old versions: the old scheme was a plain number.
            if major != other.major { return major > other.major }
            if month != other.month { return month > other.month }
            return patch > otherPatch
        }
        if major != other.major { return major > other.major }
        if month != other.month { return month > other.month }
        if day != other.day { return day > other.day }
        return build > other.build
    }
}
