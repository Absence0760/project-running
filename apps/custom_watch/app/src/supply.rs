//! One boot-time line about how the SoC is being supplied, and a refusal to be
//! quiet when that combination cannot drive the breakouts.
//!
//! **The problem this exists for.** The nRF52840 has two supply paths. Fed on
//! VDD it runs in normal mode and its GPIO high level *is* the rail you gave
//! it. Fed on VDDH it runs in high-voltage mode, and VDD — the rail that sets
//! every GPIO's logic high — comes from an internal regulator whose output is
//! `UICR.REGOUT0`, **defaulting to 1.8 V on an erased UICR**.
//!
//! On the nRF52840 DK that is not an exotic configuration; it is what happens
//! the moment the kit is run off its Li-Po connector, because SW9's Li-Po
//! position feeds the SoC's high-voltage regulator. So the untethered build —
//! the only one § 82's outdoor run can use — is exactly the one that can come
//! up at 1.8 V logic against breakouts sitting on a 3 V rail. Every one of them
//! (Sharp MIP, BMP581, MAX-M10S, MAX30101) is a 3-5 V logic part, so the
//! failure is not subtle: the display's level shifter may not see a valid high,
//! and the GPS driving its 3 V UART into a 1.8 V input is over-voltage on the
//! pin, not merely a marginal level.
//!
//! **Read-only, deliberately.** Programming `REGOUT0` from firmware would fix
//! it in one write, and it is not done here: the write must be followed by a
//! reset to take effect, and a reset loop is the failure mode if the write does
//! not stick — on a simulator that models UICR loosely, or on a part whose UICR
//! page has already been written. A boot that reports a wrong supply is
//! recoverable by anyone reading the log; a boot that resets forever is not.
//! The fix is a one-time host-side step, recorded in `docs/custom_watch/parts.md`.

use defmt::*;
use embassy_nrf::pac;
use pac::power::vals::Mainregstatus;
use pac::uicr::vals::Vout;

/// Log the supply mode, and warn loudly if it cannot drive 3 V peripherals.
pub fn report() {
    let mode = pac::POWER.mainregstatus().read().mainregstatus();
    let vout = pac::UICR.regout0().read().vout();
    match mode {
        Mainregstatus::NORMAL => {
            // VDD is whatever the board regulator supplies; REGOUT0 does not
            // apply, so there is nothing here that can be misconfigured.
            info!("supply: normal mode (VDD) — GPIO level follows the board rail");
        }
        Mainregstatus::HIGH => match vout {
            Vout::DEFAULT | Vout::_1V8 => error!(
                "supply: HIGH-voltage mode (VDDH) with REGOUT0 unset — GPIO logic is 1.8 V. \
                 The 3 V breakouts will not read it, and their outputs over-volt these pins. \
                 Program UICR.REGOUT0 to 3.0 V before wiring them (docs/custom_watch/parts.md)"
            ),
            Vout::_2V1 | Vout::_2V4 | Vout::_2V7 => warn!(
                "supply: HIGH-voltage mode (VDDH), REGOUT0 below 3.0 V — breakout logic margins are not guaranteed"
            ),
            _ => info!("supply: HIGH-voltage mode (VDDH), REGOUT0 at 3.0 V or above"),
        },
    }
}
