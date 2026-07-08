/* Linker memory layout for the nRF52840 WITH the Nordic S140 7.x SoftDevice.
 *
 * Selected by build.rs when the `ble` feature is on (README step 6). The
 * SoftDevice occupies the bottom 156 KiB of flash and a run-time-determined
 * slice of the bottom of RAM, so the application is linked above both.
 *
 *   FLASH: app starts at 0x00027000 (156 KiB), the S140 7.3.0 code region.
 *   RAM  : app starts 31 KiB up. This RAM reservation is the SoftDevice's
 *          *maximum* footprint for our connection config; the actual required
 *          start address is printed by `Softdevice::enable` at boot
 *          ("sd_ble_enable: RAM start should be ..."). BENCH-TUNE this ORIGIN
 *          down to that reported value once the dev kit is attached — over-
 *          reserving here only wastes RAM, it does not misbehave.
 *
 * Mirrors nrf-softdevice's own examples/memory-nrf52840.x for S140 7.3.0.
 * The non-SoftDevice layout (default / sim builds) stays in memory.x.
 *
 * Flashing: the S140 hex must be programmed once alongside the app
 * (`probe-rs download s140_nrf52_7.3.0_softdevice.hex --binary-format hex`),
 * then the app flashes normally. See apps/custom_watch/README.md step 6.
 */

MEMORY
{
  /* NOTE 1 K = 1 KiBi = 1024 bytes */
  FLASH : ORIGIN = 0x00000000 + 156K, LENGTH = 1024K - 156K
  RAM   : ORIGIN = 0x20000000 + 31K,  LENGTH = 256K - 31K
}
