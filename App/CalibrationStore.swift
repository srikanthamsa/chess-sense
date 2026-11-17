import Foundation

/// Persists the learned template book and board rect.
///
/// `UserDefaults.standard` is deliberate for v1: an App Intent triggered from a Shortcut
/// runs in the app's own process, so it can read the same defaults. Promote this to a
/// shared App Group container once a widget needs to read calibration on its own.
struct CalibrationStore {
    private enum Keys {
        static let book = "chesssense.templateBook.v1"
        static let rect = "chesssense.boardRect.v1"
        static let calibratedAt = "chesssense.calibratedAt.v1"
        static let trackedFEN = "chesssense.trackedFEN.v1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var calibrationDate: Date? {
        defaults.object(forKey: Keys.calibratedAt) as? Date
    }

    var isCalibrated: Bool {
        defaults.data(forKey: Keys.book) != nil && defaults.data(forKey: Keys.rect) != nil
    }

    func save(book: TemplateBook, rect: BoardRect) throws {
        let encoder = JSONEncoder()
        defaults.set(try encoder.encode(book), forKey: Keys.book)
        defaults.set(try encoder.encode(rect), forKey: Keys.rect)
        defaults.set(Date(), forKey: Keys.calibratedAt)
    }

    func loadBook() -> TemplateBook? {
        guard let data = defaults.data(forKey: Keys.book) else { return nil }
        return try? JSONDecoder().decode(TemplateBook.self, from: data)
    }

    /// Position after the last analysed frame. This is what makes side-to-move,
    /// castling rights and en passant survive between App Intent runs.
    var trackedFEN: String? {
        get { defaults.string(forKey: Keys.trackedFEN) }
        nonmutating set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.trackedFEN)
            } else {
                defaults.removeObject(forKey: Keys.trackedFEN)
            }
        }
    }

    func resetTracking() {
        defaults.removeObject(forKey: Keys.trackedFEN)
    }

    func loadRect() -> BoardRect? {
        guard let data = defaults.data(forKey: Keys.rect) else { return nil }
        return try? JSONDecoder().decode(BoardRect.self, from: data)
    }

    func reset() {
        resetTracking()
        defaults.removeObject(forKey: Keys.book)
        defaults.removeObject(forKey: Keys.rect)
        defaults.removeObject(forKey: Keys.calibratedAt)
    }
}
