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
use embassy_nrf::nvmc::Nvmc;
use embassy_nrf::{bind_interrupts, peripherals, spim, twim, uarte};
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
    let (_gps_tx, gps_rx) = gps_uart.split();

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

    // Buttons are active-LOW with the line idle-high, so pull up and treat a
    // press as a falling edge (see the `button` task). BTN3 cycles the page.
    let btn1 = Input::new(board.buttons.btn1, Pull::Up);
    let btn2 = Input::new(board.buttons.btn2, Pull::Up);
    let btn3 = Input::new(board.buttons.btn3, Pull::Up);

    // Shared flash run store: `record` commits finished runs, `ble` reads them
    // back for sync. Probes for the NVMC controller at construction and no-ops
    // if it is absent (the sim), so recording is never blocked on flash.
    static STORE: StaticCell<run_flash::SharedStore> = StaticCell::new();
    let store = STORE.init(Mutex::new(run_flash::RunStore::new(Nvmc::new(
        board.flash.nvmc,
    ))));

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
    spawner.spawn(unwrap!(tasks::ui::screen_task(display_spi, display_cs)));
    spawner.spawn(unwrap!(tasks::button::run(btn1, btn2, btn3)));
    spawner.spawn(unwrap!(tasks::gps::run(gps_rx)));
    spawner.spawn(unwrap!(tasks::hr::run(hr_twim)));
    spawner.spawn(unwrap!(tasks::baro::run(baro_twim)));
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
        let (phone_tx, _phone_rx) = phone_uart.split();
        spawner.spawn(unwrap!(tasks::phone::run(phone_tx)));
        spawner.spawn(unwrap!(tasks::ble::run()));
    }

    #[cfg(feature = "ble")]
    {
        use static_cell::StaticCell;
        // `enable` hands back &'static mut; `Server::new` needs the &mut to
        // register attributes, after which we reborrow it as a shared &'static
        // for the two tasks that share the stack.
        let sd = Softdevice::enable(&tasks::ble::config());
        static SERVER: StaticCell<tasks::ble::Server> = StaticCell::new();
        let server = SERVER.init(unwrap!(tasks::ble::Server::new(sd)));
        let sd: &'static Softdevice = sd;
        spawner.spawn(unwrap!(tasks::ble::softdevice_task(sd)));
        spawner.spawn(unwrap!(tasks::ble::run(sd, server, store)));
    }
}
