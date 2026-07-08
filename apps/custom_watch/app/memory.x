/* Linker memory layout for the Nordic nRF52840.
 * - 1 MB flash starting at 0x00000000
 * - 256 KB RAM starting at 0x20000000
 *
 * Tier-1 layout (current): no SoftDevice, no bootloader. Flash minus the
 * run-store region + all RAM available for the application.
 *
 * The top 16K of flash is reserved for the on-device run store (README step 7,
 * watch_core::flash_store: 4 slots x one 4K erase page). FLASH LENGTH is shrunk
 * by exactly that 16K so the linker never places code in the region; the NVMC
 * driver still addresses it by absolute offset (FLASH_SIZE - 16K = 0xFC000).
 * This 16K MUST equal watch_core::flash_store::REGION_LEN — keep them in step.
 *
 * Tier-1 step 6 (BLE bring-up via nrf-softdevice) reorganises: FLASH ORIGIN
 * moves up to 0x27000 (S140 7.x SoftDevice region), LENGTH reduces to ~860K
 * (see memory-ble.x, which reserves the same top-of-flash run-store region).
 *
 * Tier-2 (per decisions.md § 84) further carves out an MCUboot bootloader
 * (~32K) + dual-bank application slots (~400K each) from the post-SoftDevice
 * region, and moves run storage to external QSPI flash. Exact layout TBD at
 * tier-2 design time; documented here so a future reader sees the plan even
 * though it's not implemented at tier 1.
 */

MEMORY
{
  FLASH     : ORIGIN = 0x00000000, LENGTH = 1024K - 16K
  RUN_STORE : ORIGIN = 0x00000000 + 1024K - 16K, LENGTH = 16K
  RAM       : ORIGIN = 0x20000000, LENGTH = 256K
}
