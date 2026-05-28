/* Linker memory layout for the Nordic nRF52840.
 * - 1 MB flash starting at 0x00000000
 * - 256 KB RAM starting at 0x20000000
 *
 * Tier-1 layout (current): no SoftDevice, no bootloader. Whole flash + RAM
 * available for the application.
 *
 * Tier-1 step 6 (BLE bring-up via nrf-softdevice) reorganises: FLASH ORIGIN
 * moves up to 0x27000 (S140 7.x SoftDevice region), LENGTH reduces to ~860K.
 *
 * Tier-2 (per decisions.md § 84) further carves out an MCUboot bootloader
 * (~32K) + dual-bank application slots (~400K each) from the post-SoftDevice
 * region. Exact layout TBD at tier-2 design time; documented here so a future
 * reader sees the plan even though it's not implemented at tier 1.
 */

MEMORY
{
  FLASH : ORIGIN = 0x00000000, LENGTH = 1024K
  RAM   : ORIGIN = 0x20000000, LENGTH = 256K
}
