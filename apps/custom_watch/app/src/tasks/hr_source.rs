//! HR arbiter — the single publisher of `state::HR`.
//!
//! Two sensors can report a pulse: the on-wrist optical AFE (`hr`, always) and
//! an external BLE chest strap (`hr_strap`, `ble` builds only). Letting both
//! write the shared watch would make precedence emergent — whichever task
//! happened to write last would win, and a strap lying on a table would beat a
//! wrist that is actually being worn. This task owns the seam instead, and the
//! rule it applies is `watch_core::hr_source::select_hr`: a strap reporting a
//! trusted rate no older than `STRAP_STALE_AFTER_S` outranks the optical
//! sensor, anything else falls back to it, and with neither the watch blanks.
//!
//! It sleeps on its two inputs and arms exactly one timer — the deadline a
//! held strap sample expires at (`strap_recheck_wait_s`), so a strap that
//! simply stops, on a watch with no optical sensor to wake anything, still
//! blanks on time instead of holding its last rate for a whole
//! `hr_duty::hold_budget_s`. No polling, no free-running waker.
//!
//! Present on every build. Without the `ble` feature nothing ever writes the
//! strap seam, so this forwards the optical sensor unchanged.

use defmt::*;
use embassy_futures::select::{select, select3, Either, Either3};
use embassy_time::{Duration, Instant, Timer};
use watch_core::hr_duty::HrSample;
use watch_core::hr_source::{self, HrSource};

use crate::state;

#[embassy_executor::task]
pub async fn run() -> ! {
    let mut optical_rx = unwrap!(state::HR_OPTICAL.receiver());
    let mut strap_rx = unwrap!(state::HR_STRAP.receiver());
    let sender = state::HR.sender();
    let mut optical: Option<HrSample> = None;
    let mut strap: Option<HrSample> = None;
    let mut published: Option<HrSample> = None;
    let mut logged_source: Option<Option<HrSource>> = None;
    loop {
        let now_s = Instant::now().as_secs() as u32;
        if let Some(sample) = hr_source::hr_to_publish(published, strap, optical, now_s) {
            sender.send(sample);
            published = Some(sample);
        }
        let source = hr_source::select_hr(strap, optical, now_s).map(|s| s.source);
        if logged_source != Some(source) {
            match source {
                Some(s) => info!("hr_source: {:?} authoritative", s),
                None => info!("hr_source: no trusted pulse"),
            }
            logged_source = Some(source);
        }

        match hr_source::strap_recheck_wait_s(strap, now_s) {
            Some(wait_s) => {
                match select3(
                    optical_rx.changed(),
                    strap_rx.changed(),
                    Timer::after(Duration::from_secs(u64::from(wait_s))),
                )
                .await
                {
                    Either3::First(s) => optical = Some(s),
                    Either3::Second(s) => strap = Some(s),
                    Either3::Third(()) => {}
                }
            }
            None => match select(optical_rx.changed(), strap_rx.changed()).await {
                Either::First(s) => optical = Some(s),
                Either::Second(s) => strap = Some(s),
            },
        }
    }
}
