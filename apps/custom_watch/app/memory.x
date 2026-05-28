/* Linker memory layout for the Nordic nRF52840.
 * - 1 MB flash starting at 0x00000000
 * - 256 KB RAM starting at 0x20000000
 * When `nrf-softdevice` is added in step 6, the FLASH ORIGIN moves up past
 * the SoftDevice region (typically 0x27000 for S140 7.x). Update both
 * ORIGIN values + reduce LENGTH accordingly when that change lands.
 */

MEMORY
{
  FLASH : ORIGIN = 0x00000000, LENGTH = 1024K
  RAM   : ORIGIN = 0x20000000, LENGTH = 256K
}
