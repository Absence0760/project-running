/* Linker memory layout for the Nordic nRF52840.
 * - 1 MB flash starting at 0x00000000
 * - 256 KB RAM starting at 0x20000000
 *
 * Tier-1 layout (current): no SoftDevice, no bootloader. Flash minus the
 * run-store region + all RAM available for the application.
 *
 * The top 16K of flash is reserved for the on-device run store (README step 7,
 * watch_core::flash_store: 4 slots x one 4K erase page). Immediately BELOW it
 * TWO further 4K erase pages hold the persisted-config records (GNSS mode, BLE
 * bond, waypoints, ICE card, composed screens, timer, race config;
 * watch_core::flash_store::CONFIG_REGION_LEN; addressed at absolute 0xFA000 via
 * app run_flash::CONFIG_REGION_OFFSET). There are two because a rewrite writes
 * the page that is not live and only then seals it, so a brown-out inside the
 * 85 ms erase leaves the previous page whole instead of taking every record on
 * the page at once. FLASH LENGTH is shrunk by exactly 16K + 8K so the linker
 * never places code in either region; the NVMC driver addresses them by absolute
 * offset (run store at FLASH_SIZE - 16K = 0xFC000, config pages at 0xFA000 and
 * 0xFB000). The run-store region base is UNCHANGED by the config pages sitting
 * below it. The 16K MUST equal watch_core::flash_store::REGION_LEN and the 8K
 * watch_core::flash_store::CONFIG_REGION_LEN — keep them in step.
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
  FLASH     : ORIGIN = 0x00000000, LENGTH = 1024K - 16K - 8K
  CONFIG    : ORIGIN = 0x00000000 + 1024K - 16K - 8K, LENGTH = 8K
  RUN_STORE : ORIGIN = 0x00000000 + 1024K - 16K, LENGTH = 16K
  RAM       : ORIGIN = 0x20000000, LENGTH = 256K
}
