import Darwin
import Foundation

/// An OS-owned lock that prevents two raw MacSnap executables from running together.
/// The kernel releases it automatically on exit or crash, so it cannot become stale.
final class SingleInstanceLock {
    private let descriptor: Int32

    init?(path: String = "/tmp/com.macsnap.app.instance.lock") {
        let fd = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return nil
        }
        descriptor = fd
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
