// Copy memory.x into the build output so cortex-m-rt's linker script can find it.
// Required for the nRF52840's flash + RAM layout.

use std::env;
use std::fs::File;
use std::io::Write;
use std::path::PathBuf;

fn main() {
    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    // The `ble` feature links above the S140 SoftDevice, so it needs a
    // different flash + RAM origin. Both variants are emitted as `memory.x`
    // into OUT_DIR; only one is compiled per build, keeping the default / sim
    // layout byte-identical to what it was before BLE landed.
    let memory_x: &[u8] = if env::var_os("CARGO_FEATURE_BLE").is_some() {
        include_bytes!("memory-ble.x")
    } else {
        include_bytes!("memory.x")
    };
    File::create(out.join("memory.x"))
        .unwrap()
        .write_all(memory_x)
        .unwrap();
    println!("cargo:rustc-link-search={}", out.display());
    println!("cargo:rerun-if-changed=memory.x");
    println!("cargo:rerun-if-changed=memory-ble.x");
    println!("cargo:rerun-if-changed=build.rs");
}
