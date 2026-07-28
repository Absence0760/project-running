//! custom_watch tier-1 firmware — entry point.
//!
//! Boots the Embassy async runtime, splits the board into per-subsystem
//! ports (`nrf52840_dk::Board`), and spawns one task per subsystem. Tasks
//! are thin peripheral glue; the logic they drive lives in the host-tested
//! `watch_core` + driver crates.
//!
//! The `ble` feature (README step 6) enables the Nordic S140 SoftDevice and
//! carries the phone link over the radio instead of UARTE1. It is mutually
//! exclusive with the default `single-core-cs` feature and CANNOT run under
//! the Renode sim — build it with `--no-default-features --features ble`.
//!
//! See `apps/custom_watch/README.md` for the per-step bring-up plan.

#![no_std]
#![no_main]

use defmt::*;
use embassy_executor::Spawner;
use embassy_nrf::gpio::{Input, Level, Output, OutputDrive, Pull};
#[cfg(not(feature = "ble"))]
use embassy_nrf::nvmc::Nvmc;
use embassy_nrf::{bind_interrupts, peripherals, saadc, spim, twim, uarte};
use embassy_sync::mutex::Mutex;
use nrf52840_dk::Board;
use static_cell::StaticCell;
use {defmt_rtt as _, panic_probe as _};

#[cfg(feature = "ble")]
use nrf_softdevice::Softdevice;

mod run_flash;
mod state;
mod tasks;

bind_interrupts!(struct Irqs {
    UARTE0 => uarte::InterruptHandler<peripherals::UARTE0>;
    UARTE1 => uarte::InterruptHandler<peripherals::UARTE1>;
    SPIM3 => spim::InterruptHandler<peripherals::SPI3>;
    TWISPI0 => twim::InterruptHandler<peripherals::TWISPI0>;
    TWISPI1 => twim::InterruptHandler<peripherals::TWISPI1>;
    SAADC => saadc::InterruptHandler;
});

#[embassy_executor::main]
async fn main(spawner: Spawner) {
    // The SoftDevice reserves interrupt priorities 0, 1 and 4 for the radio.
    // The app must keep every interrupt it enables off those levels, so the
    // BLE build raises Embassy's GPIOTE + RTC time-driver priorities and then
    // lowers each peripheral IRQ below the reserved band. The default build
    // has the whole NVIC to itself and uses the stock config.
    #[cfg(feature = "ble")]
    let p = {
        use embassy_nrf::interrupt::{self, InterruptExt, Priority};
        let mut config = embassy_nrf::config::Config::default();
        config.gpiote_interrupt_priority = Priority::P2;
        config.time_interrupt_priority = Priority::P2;
        let p = embassy_nrf::init(config);
        interrupt::UARTE0.set_priority(Priority::P2);
        interrupt::SPIM3.set_priority(Priority::P2);
        interrupt::TWISPI0.set_priority(Priority::P2);
        interrupt::TWISPI1.set_priority(Priority::P2);
        interrupt::SAADC.set_priority(Priority::P2);
        p
    };
    #[cfg(not(feature = "ble"))]
    let p = embassy_nrf::init(Default::default());

    let board = Board::split(p);
    info!("custom_watch firmware booting (tier 1)");

    let mut gps_config = uarte::Config::default();
    gps_config.baudrate = uarte::Baudrate::BAUD9600;
    let gps_uart = uarte::Uarte::new(
        board.gps.uarte,
        board.gps.rx,
        board.gps.tx,
        Irqs,
        gps_config,
    );
    // TX carries the UBX-RXM-PMREQ power-down frames + the 0xFF wake byte the
    // gps task sends to duty-cycle the receiver in throttled recording modes.
    let (gps_tx, gps_rx) = gps_uart.split();

    // Sharp MIP wants LSB-first (datasheet bit M0 leads) and mode 0; the
    // panel tops out at 2 MHz.
    let mut spi_config = spim::Config::default();
    spi_config.frequency = spim::Frequency::M2;
    spi_config.bit_order = spim::BitOrder::LSB_FIRST;
    let display_spi = spim::Spim::new_txonly(
        board.display.spim,
        Irqs,
        board.display.sck,
        board.display.mosi,
        spi_config,
    );
    // Active-HIGH chip select: idle low.
    let display_cs = Output::new(board.display.cs, Level::Low, OutputDrive::Standard);

    // EasyDMA can't source a write from flash, so the TWIM needs a RAM buffer
    // for its outgoing bytes; the driver's writes are 2 bytes, 16 is ample.
    static mut HR_TWIM_RAM: [u8; 16] = [0; 16];
    let mut hr_i2c_config = twim::Config::default();
    hr_i2c_config.frequency = twim::Frequency::K400;
    hr_i2c_config.sda_pullup = true;
    hr_i2c_config.scl_pullup = true;
    let hr_twim = twim::Twim::new(
        board.hr.twim,
        Irqs,
        board.hr.sda,
        board.hr.scl,
        hr_i2c_config,
        unsafe { &mut *core::ptr::addr_of_mut!(HR_TWIM_RAM) },
    );

    static mut BARO_TWIM_RAM: [u8; 16] = [0; 16];
    let mut baro_i2c_config = twim::Config::default();
    baro_i2c_config.frequency = twim::Frequency::K400;
    baro_i2c_config.sda_pullup = true;
    baro_i2c_config.scl_pullup = true;
    let baro_twim = twim::Twim::new(
        board.baro.twim,
        Irqs,
        board.baro.sda,
        board.baro.scl,
        baro_i2c_config,
        unsafe { &mut *core::ptr::addr_of_mut!(BARO_TWIM_RAM) },
    );

    // Battery gauge: the SAADC's internal VDD channel — the rail itself is the
    // input, no pin to route. Driver defaults (12-bit, 0.6 V internal
    // reference, gain 1/6 -> 3.6 V full scale) suit a supply read; the task
    // owns the conversion maths and the plausibility park.
    let battery_adc = saadc::Saadc::new(
        board.battery.saadc,
        Irqs,
        saadc::Config::default(),
        [saadc::ChannelConfig::single_ended(saadc::VddInput)],
    );

    // Buttons are active-LOW with the line idle-high, so pull up and treat a
    // press as a falling edge (see the `button` task). BTN3/BTN4 page left /
    // right (BTN3 idle: the GNSS mode), BTN5 takes the manual lap (§350).
    let btn1 = Input::new(board.buttons.btn1, Pull::Up);
    let btn2 = Input::new(board.buttons.btn2, Pull::Up);
    let btn3 = Input::new(board.buttons.btn3, Pull::Up);
    let btn4 = Input::new(board.buttons.btn4, Pull::Up);
    let btn5 = Input::new(board.buttons.btn5, Pull::Up);

    // The BLE build brings the SoftDevice up before the run store because the
    // S140 arbitrates all flash access: the store's backend there is
    // `nrf_softdevice::Flash`, which needs the enabled stack. Its background
    // task is spawned here too, ahead of any flash erase/write — those complete
    // via SoC events only that task dispatches.
    #[cfg(feature = "ble")]
    let (sd, server) = {
        // `enable` hands back &'static mut; `Server::new` needs the &mut to
        // register attributes, after which we reborrow it as a shared &'static
        // for the two tasks that share the stack.
        let sd = Softdevice::enable(&tasks::ble::config());
        static SERVER: StaticCell<tasks::ble::Server> = StaticCell::new();
        let server = SERVER.init(unwrap!(tasks::ble::Server::new(sd)));
        let sd: &'static Softdevice = sd;
        spawner.spawn(unwrap!(tasks::ble::softdevice_task(sd)));
        (sd, server)
    };

    // Shared flash run store: `record` commits finished runs, `ble` reads them
    // back for sync. Default build: embassy-nrf NVMC, probed at construction
    // and no-op'd when absent (the sim), so recording is never blocked on
    // flash. BLE build: the SoftDevice-arbitrated flash handle taken above.
    #[cfg(not(feature = "ble"))]
    let flash = Nvmc::new(board.flash.nvmc);
    #[cfg(feature = "ble")]
    let flash = nrf_softdevice::Flash::take(sd);
    static STORE: StaticCell<run_flash::SharedStore> = StaticCell::new();
    let store = STORE.init(Mutex::new(run_flash::RunStore::new(flash)));

    // Boot-seed the persisted GNSS recording mode so a deliberate Expedition /
    // Balanced choice survives reboot / brown-out instead of silently reverting
    // to the Performance default. Best-effort / L4: no saved (or unreadable)
    // config reads as `None` and the default stands. Publish it to
    // `state::GNSS_MODE` for the gps / record / ui consumers, and hand it to the
    // button task so its BTN3 cycle continues from the restored mode rather than
    // jumping back to Performance on the first idle press.
    let boot_mode = {
        let saved = store.lock().await.read_gnss_mode();
        if let Some(mode) = saved {
            state::GNSS_MODE.sender().send(mode);
            info!("boot: restored GNSS mode {} from flash", mode);
        }
        saved.unwrap_or_default()
    };

    // Boot-seed the last-applied activity profile (§353) the same way, so the
    // menu's PROFILE row reads the restored selection and the record task can
    // re-apply the profile's page preset. `None` (no stored choice, or a
    // corrupt byte) leaves the row an honest `--`.
    let boot_profile = {
        let saved = store.lock().await.read_profile();
        if let Some(p) = saved {
            info!("boot: restored activity profile {} from flash", p);
        }
        state::PROFILE.sender().send(saved);
        saved
    };

    // The liveness LED is a debug affordance behind the default-OFF `dev-blink`
    // feature — a free-running 2 Hz waker has no place in the lean build.
    #[cfg(feature = "dev-blink")]
    spawner.spawn(unwrap!(tasks::ui::blink_task(board.leds.led1)));
    // Hardware VCOM: a free-running PWM on EXTCOMIN (EXTMODE high) toggles the
    // panel bias so the screen task never wakes just to maintain it.
    spawner.spawn(unwrap!(tasks::ui::vcom_task(
        board.display.pwm,
        board.display.extcomin,
        board.display.extmode,
    )));
    // The breadcrumb course, when this build carries one (the canned course
    // behind `sim-course`): the nav task projects fixes onto it, the screen
    // task draws it on the Nav page. One shared &'static, built once.
    let course = tasks::nav::course();
    spawner.spawn(unwrap!(tasks::ui::screen_task(
        display_spi,
        display_cs,
        course
    )));
    spawner.spawn(unwrap!(tasks::button::run(
        btn1,
        btn2,
        btn3,
        btn4,
        btn5,
        (boot_mode, boot_profile),
        store
    )));
    spawner.spawn(unwrap!(tasks::gps::run(gps_tx, gps_rx)));
    spawner.spawn(unwrap!(tasks::nav::run(course)));
    spawner.spawn(unwrap!(tasks::hr::run(hr_twim)));
    spawner.spawn(unwrap!(tasks::baro::run(baro_twim)));
    spawner.spawn(unwrap!(tasks::battery::run(battery_adc)));
    spawner.spawn(unwrap!(tasks::record::run(store)));

    // Phone link. Default build: UARTE1 → Renode TCP bridge, plus the BLE
    // stub. BLE build: the S140 SoftDevice owns the link over the radio and
    // UARTE1 is left free.
    #[cfg(not(feature = "ble"))]
    {
        let phone_uart = uarte::Uarte::new(
            board.phone.uarte,
            board.phone.rx,
            board.phone.tx,
            Irqs,
            uarte::Config::default(),
        );
        let (phone_tx, phone_rx) = phone_uart.split();
        spawner.spawn(unwrap!(tasks::phone::run(phone_tx)));
        spawner.spawn(unwrap!(tasks::phone::settings_rx(phone_rx)));
        spawner.spawn(unwrap!(tasks::ble::run()));
    }

    #[cfg(feature = "ble")]
    {
        // The bonding security handler outlives every connection (the
        // SoftDevice holds a &'static): one remembered phone, keys persisted
        // to the flash config page by the ble task (issue #598).
        static BONDER: StaticCell<tasks::ble::Bonder> = StaticCell::new();
        let bonder = BONDER.init(tasks::ble::Bonder::default());
        spawner.spawn(unwrap!(tasks::ble::run(sd, server, store, bonder)));
        // Separate from the serve loop so a disconnect racing a fresh bond
        // can't cancel the flash persist mid-write (see bond_persist's doc).
        spawner.spawn(unwrap!(tasks::ble::bond_persist(store, bonder)));
    }
}
