//! The lock holder of TC-112-001 (c): a child process that holds an exclusive lock on a file
//! until it is killed (as a live server holds its name). The test that needs it starts its
//! own binary again with LOCK_HOLDER set; a guard at the test's top runs `hold` instead.

/// The variable that names the lock file, and the line the holder prints once it holds it.
pub const LOCK_HOLDER: &str = "WSTX_TEST_LOCK_HOLDER";
pub const LOCKED: &str = "lock-holder: locked";

/// Holds an exclusive lock on `path` and prints LOCKED; returns when stdin closes.
pub fn hold(path: impl AsRef<std::path::Path>) {
    let file = std::fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(path)
        .unwrap();
    file.lock().unwrap();
    println!("{LOCKED}");
    // Held until killed; a parent that ends without killing it closes this pipe.
    let _ = std::io::Read::read_to_end(&mut std::io::stdin(), &mut Vec::new());
}
