//! The panic handler.
//!
//! Its own module because `main.rs` does `use defmt::*`, which glob-imports
//! defmt's `panic_handler` attribute macro and makes the bare `#[panic_handler]`
//! ambiguous with the built-in one. Nothing here glob-imports defmt, so the
//! attribute means what it says.

/// Print the panic, then the state that says what kind of panic it was.
///
/// Replaces `panic_probe`, whose behaviour the first two statements reproduce
/// exactly: the message still contains "panicked" — the string
/// `sim/ci_smoke.py` scans every scenario's log for — and the halt is still a
/// halt.
///
/// What it adds is [`crate::state::dump_watches`], for issue #713. That panic
/// (`RefCell already mutably borrowed`) is raised inside
/// `embassy_sync::watch`'s generic code, so it can name a source line but never
/// which of the 37 `Watch`es was involved, and 12 local reproduction attempts
/// came back clean at a CI rate of roughly 1 in 30. Rather than keep spending
/// runs trying to catch it live, the next natural occurrence carries its own
/// diagnosis — and the borrow flag's VALUE is what separates the two live
/// explanations: a genuine double borrow leaves a legitimate count there, the
/// corruption of #754 would leave something that was never a count.
///
/// Interrupts are masked first so the dump is a coherent snapshot rather than
/// one taken while tasks still run underneath it.
///
/// **The dump goes first and the message last, deliberately.** defmt-rtt's ring
/// overwrites oldest-first when the host has not drained it, and a panic emits
/// everything at once with no chance to drain in between — so whatever is
/// printed LAST is what survives. The `panicked` line is the one
/// `sim/ci_smoke.py` scans for, and losing it would turn a panic back into a
/// scenario failing on some unrelated assertion, which is the exact
/// misattribution § 582 exists to stop. Measured, not assumed: dumping all 37
/// structs whole and printing the message first left only the final 5 lines in
/// the log and no `panicked` at all.
#[panic_handler]
fn panic(info: &core::panic::PanicInfo) -> ! {
    cortex_m::interrupt::disable();
    crate::state::dump_watches();
    // No prefix: `PanicInfo`'s own Display already opens with "panicked at",
    // which is the substring `ci_smoke.py` scans for.
    defmt::error!("{}", defmt::Display2Format(info));
    cortex_m::asm::udf()
}
