import os

extension Logger {
    /// Every LiricoKit module logs under one subsystem, so a single
    /// `subsystem == "com.fabiogaliano.LiricoKit"` predicate shows all of them.
    package static func liricoKit(category: String) -> Logger {
        Logger(subsystem: "com.fabiogaliano.LiricoKit", category: category)
    }
}
