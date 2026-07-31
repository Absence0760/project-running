//
// BMP581 — a Renode model of the Bosch BMP581 barometric pressure sensor's
// I2C register interface, fed by a deterministic, monitor-scriptable
// altitude source.
//
// Speaks the register protocol the drivers/bmp581 crate drives (see
// drivers/bmp581/src/lib.rs): CHIP_ID (0x01) answers the probe with 0x50,
// CMD (0x7E) soft-reset returns the config registers to power-on defaults,
// the OSR/IIR/ODR config writes are stored and read back verbatim,
// INT_STATUS (0x27) reports data-ready only while the pwr_mode field says
// the sensor is converting (Standby reads not-ready, matching the driver's
// standby-while-configuring window), and the data registers serve the
// 3-byte pressure burst (PRESS_DATA_XLSB 0x20..0x22) and the 6-byte
// temp+press burst (TEMP_DATA_XLSB 0x1D..0x22) as little-endian 24-bit
// fixed-point counts: pressure = Pa * 64, temperature = °C * 2^16 (signed).
// The register pointer auto-increments across a burst; a sample is latched
// per transaction, so a burst read is coherent.
//
// The pressure source is scripted — never random, never wall-clock. Either a
// static altitude (SetAltitudeMeters) or a triangle profile
// (StartTriangleProfile) advanced by a 1 Hz LimitTimer on the machine's
// virtual-time clock source, so a given firmware + fixture + profile run is
// reproducible. The same timer can ramp the sea-level reference
// (StartSeaLevelTrend) — a WEATHER change rather than a movement one, which is
// the only way to make the station pressure fall while the altitude the
// firmware sees from GPS stays put. Altitude converts to pressure by inverting the same
// international-barometric-formula constants the firmware applies
// (watch_core::elevation::altitude_m — scale 44330 m, exponent 0.190295),
// referenced to a settable sea-level pressure (default: the ISA standard
// 101325 Pa the firmware also defaults to, so firmware-computed altitude
// tracks the scripted altitude). Temperature follows the ISA lapse
// (15 °C - 6.5 °C/km).
//
// Monitor usage (attach via bin/watch-monitor.sh):
//
//   sysbus.twi1.bmp581 SetAltitudeMeters 1650          # static altitude
//   sysbus.twi1.bmp581 StartTriangleProfile 1600 1800 400 600
//       # bounce between 1600 m and 1800 m, climbing at 400 mm/s and
//       # descending at 600 mm/s (those rates track the mountain_loop NMEA
//       # fixture's GPS altitude ramp, so baro and GPS co-vary for the
//       # elevation complementary filter). Starts climbing from the current
//       # altitude clamped into [low, high].
//   sysbus.twi1.bmp581 StopProfile                     # freeze where it is
//   sysbus.twi1.bmp581 SetSeaLevelPa 101800            # move the QNH reference
//   sysbus.twi1.bmp581 StartSeaLevelTrend -8           # a front arriving: drop
//       # the sea-level reference 8 Pa per virtual second. The altitude source
//       # is untouched, so this is weather and not movement — which is exactly
//       # the distinction watch_core::storm exists to make.
//   sysbus.twi1.bmp581 StopSeaLevelTrend               # freeze the reference
//   sysbus.twi1.bmp581 AltitudeMeters                  # inspect
//
// The default altitude is 1600 m — inside the canned fixtures' terrain
// (bench_jog 1624 m, mountain_loop 1600–1800 m), so the GPS-baro divergence
// the firmware's complementary filter seeds from starts realistically small.
//
using System;

using Antmicro.Renode.Core;
using Antmicro.Renode.Logging;
using Antmicro.Renode.Peripherals.I2C;
using Antmicro.Renode.Peripherals.Timers;
using Antmicro.Renode.Time;

namespace Antmicro.Renode.Peripherals.Sensors
{
    public class BMP581 : II2CPeripheral
    {
        public BMP581(IMachine machine)
        {
            profileTimer = new LimitTimer(machine.ClockSource, 1, this, "profile", limit: 1, enabled: false, eventEnabled: true);
            profileTimer.LimitReached += ProfileTick;
            altitudeMm = DefaultAltitudeMm;
            seaLevelPa = StandardSeaLevelPa;
            LatchSample();
            SoftReset();
        }

        public void Reset()
        {
            // Chip state resets; the scripted environment (altitude source,
            // sea-level reference, a running profile or weather trend)
            // deliberately survives a machine reset — the atmosphere is not
            // part of the chip.
            regPointer = 0;
            SoftReset();
        }

        public void Write(byte[] data)
        {
            if(data.Length == 0)
            {
                return;
            }
            // Byte 0 sets the register pointer; any further bytes write
            // registers sequentially (the driver only ever writes [reg, val]
            // pairs). Latch a fresh sample per transaction so a subsequent
            // burst read is coherent.
            LatchSample();
            regPointer = data[0];
            for(var i = 1; i < data.Length; i++)
            {
                WriteRegister(regPointer, data[i]);
                regPointer++;
            }
        }

        public byte[] Read(int count = 1)
        {
            var result = new byte[count];
            for(var i = 0; i < count; i++)
            {
                result[i] = ReadRegister(regPointer);
                regPointer++;
            }
            return result;
        }

        public void FinishTransmission()
        {
            // Register pointer state is per-transaction anyway (every driver
            // access re-seeds it with a write), nothing to do at STOP.
        }

        // --- monitor-scriptable pressure source ------------------------------

        // Static altitude in metres; cancels a running profile.
        public void SetAltitudeMeters(int metres)
        {
            lock(sourceLock)
            {
                profileTimer.Enabled = false;
                profileActive = false;
                altitudeMm = metres * 1000L;
            }
            this.Log(LogLevel.Info, "altitude set to {0} m (static)", metres);
        }

        // Sea-level reference (QNH) in Pa for the altitude→pressure inversion.
        // The firmware's own reference stays wherever it is configured — moving
        // this one simulates a weather change the firmware has to cope with.
        public void SetSeaLevelPa(uint pa)
        {
            lock(sourceLock)
            {
                seaLevelPa = pa;
            }
            this.Log(LogLevel.Info, "sea-level reference set to {0} Pa", pa);
        }

        // Deterministic triangle profile: climb from the current altitude
        // (clamped into [low, high]) at upMmPerSecond, bounce off the bounds,
        // descend at downMmPerSecond — advanced once per virtual second.
        public void StartTriangleProfile(int lowMetres, int highMetres, int upMmPerSecond, int downMmPerSecond)
        {
            if(lowMetres >= highMetres || upMmPerSecond <= 0 || downMmPerSecond <= 0)
            {
                this.Log(LogLevel.Error, "StartTriangleProfile needs low < high and positive rates — ignored");
                return;
            }
            lock(sourceLock)
            {
                profileLowMm = lowMetres * 1000L;
                profileHighMm = highMetres * 1000L;
                profileUpMmPerS = upMmPerSecond;
                profileDownMmPerS = downMmPerSecond;
                altitudeMm = Math.Min(Math.Max(altitudeMm, profileLowMm), profileHighMm);
                profileClimbing = true;
                profileActive = true;
                profileTimer.Enabled = true;
            }
            this.Log(LogLevel.Info, "triangle profile {0}..{1} m, +{2}/-{3} mm/s", lowMetres, highMetres, upMmPerSecond, downMmPerSecond);
        }

        // Ramp the sea-level reference by paPerSecond each virtual second — a
        // front moving in (negative) or clearing (positive). Deliberately
        // separate from the altitude profile and driven by the same timer, so a
        // scenario can run weather and movement together or either alone.
        public void StartSeaLevelTrend(int paPerSecond)
        {
            lock(sourceLock)
            {
                seaLevelTrendPaPerS = paPerSecond;
                seaLevelTrendActive = true;
                profileTimer.Enabled = true;
            }
            this.Log(LogLevel.Info, "sea-level trend {0} Pa/s from {1} Pa", paPerSecond, seaLevelPa);
        }

        public void StopSeaLevelTrend()
        {
            lock(sourceLock)
            {
                seaLevelTrendActive = false;
                if(!profileActive)
                {
                    profileTimer.Enabled = false;
                }
            }
            this.Log(LogLevel.Info, "sea-level trend stopped at {0} Pa", seaLevelPa);
        }

        public void StopProfile()
        {
            lock(sourceLock)
            {
                profileActive = false;
                if(!seaLevelTrendActive)
                {
                    profileTimer.Enabled = false;
                }
            }
            this.Log(LogLevel.Info, "profile stopped at {0} m", (decimal)altitudeMm / 1000m);
        }

        public decimal AltitudeMeters
        {
            get
            {
                lock(sourceLock)
                {
                    return (decimal)altitudeMm / 1000m;
                }
            }
        }

        public decimal PressurePa
        {
            get
            {
                lock(sourceLock)
                {
                    return (decimal)AltitudeToPressurePa(altitudeMm / 1000.0);
                }
            }
        }

        // --- internals -------------------------------------------------------

        private void ProfileTick()
        {
            lock(sourceLock)
            {
                if(seaLevelTrendActive)
                {
                    // Clamped well inside a terrestrial range so a scenario
                    // left running cannot walk the reference into the
                    // altitude formula's singularity.
                    seaLevelPa = Math.Min(Math.Max(seaLevelPa + seaLevelTrendPaPerS, 87000.0), 110000.0);
                }
                if(!profileActive)
                {
                    return;
                }
                altitudeMm += profileClimbing ? profileUpMmPerS : -profileDownMmPerS;
                if(altitudeMm >= profileHighMm)
                {
                    altitudeMm = profileHighMm;
                    profileClimbing = false;
                }
                else if(altitudeMm <= profileLowMm)
                {
                    altitudeMm = profileLowMm;
                    profileClimbing = true;
                }
            }
        }

        private void LatchSample()
        {
            double altM;
            double refPa;
            lock(sourceLock)
            {
                altM = altitudeMm / 1000.0;
                refPa = seaLevelPa;
            }
            var pressurePa = AltitudeToPressurePa(altM, refPa);
            latchedPressRaw = (uint)Math.Round(pressurePa * 64.0) & 0xFFFFFF;
            var temperatureC = 15.0 - 0.0065 * altM;
            latchedTempRaw = (uint)(int)Math.Round(temperatureC * 65536.0) & 0xFFFFFF;
        }

        private double AltitudeToPressurePa(double altM)
        {
            return AltitudeToPressurePa(altM, seaLevelPa);
        }

        private static double AltitudeToPressurePa(double altM, double refPa)
        {
            // Inverse of watch_core::elevation::altitude_m:
            //   alt = 44330 * (1 - (p/p0)^0.190295)
            // → p = p0 * (1 - alt/44330)^(1/0.190295)
            return refPa * Math.Pow(1.0 - altM / BaroScaleM, 1.0 / BaroExponent);
        }

        private byte ReadRegister(byte reg)
        {
            switch(reg)
            {
                case RegChipId:
                    return ChipId;
                case RegIntStatus:
                    // Data-ready whenever the sensor is converting (Normal /
                    // Forced / Continuous): the configured 50 Hz ODR outruns
                    // the firmware's 1 Hz poll, so a fresh sample is always
                    // latched by the next read. Standby has no conversions.
                    return PowerMode == PowerModeStandby ? (byte)0x00 : IntStatusDrdy;
                case RegTempXlsb:
                    return (byte)(latchedTempRaw & 0xFF);
                case RegTempLsb:
                    return (byte)((latchedTempRaw >> 8) & 0xFF);
                case RegTempMsb:
                    return (byte)((latchedTempRaw >> 16) & 0xFF);
                case RegPressXlsb:
                    return (byte)(latchedPressRaw & 0xFF);
                case RegPressLsb:
                    return (byte)((latchedPressRaw >> 8) & 0xFF);
                case RegPressMsb:
                    return (byte)((latchedPressRaw >> 16) & 0xFF);
                case RegDspConfig:
                    return dspConfig;
                case RegDspIir:
                    return dspIir;
                case RegOsrConfig:
                    return osrConfig;
                case RegOdrConfig:
                    return odrConfig;
                default:
                    this.Log(LogLevel.Noisy, "read of unhandled register 0x{0:X} — returning 0", reg);
                    return 0x00;
            }
        }

        private void WriteRegister(byte reg, byte value)
        {
            switch(reg)
            {
                case RegCmd:
                    if(value == CmdSoftReset)
                    {
                        this.Log(LogLevel.Debug, "soft reset");
                        SoftReset();
                    }
                    break;
                case RegDspConfig:
                    dspConfig = value;
                    break;
                case RegDspIir:
                    dspIir = value;
                    break;
                case RegOsrConfig:
                    osrConfig = value;
                    break;
                case RegOdrConfig:
                    odrConfig = value;
                    break;
                default:
                    this.Log(LogLevel.Noisy, "write of unhandled register 0x{0:X} = 0x{1:X} — ignored", reg, value);
                    break;
            }
        }

        private void SoftReset()
        {
            dspConfig = 0x00;
            dspIir = 0x00;
            osrConfig = 0x00;
            odrConfig = 0x00; // Standby
        }

        private int PowerMode => odrConfig & 0x03;

        private byte regPointer;
        private byte dspConfig;
        private byte dspIir;
        private byte osrConfig;
        private byte odrConfig;
        private uint latchedPressRaw;
        private uint latchedTempRaw;

        private long altitudeMm;
        private double seaLevelPa;
        private bool profileActive;
        private bool seaLevelTrendActive;
        private int seaLevelTrendPaPerS;
        private bool profileClimbing;
        private long profileLowMm;
        private long profileHighMm;
        private long profileUpMmPerS;
        private long profileDownMmPerS;

        private readonly LimitTimer profileTimer;
        private readonly object sourceLock = new object();

        private const byte ChipId = 0x50;
        private const byte CmdSoftReset = 0xB6;
        private const byte IntStatusDrdy = 0x01;
        private const int PowerModeStandby = 0;

        private const byte RegChipId = 0x01;
        private const byte RegTempXlsb = 0x1D;
        private const byte RegTempLsb = 0x1E;
        private const byte RegTempMsb = 0x1F;
        private const byte RegPressXlsb = 0x20;
        private const byte RegPressLsb = 0x21;
        private const byte RegPressMsb = 0x22;
        private const byte RegIntStatus = 0x27;
        private const byte RegDspConfig = 0x30;
        private const byte RegDspIir = 0x31;
        private const byte RegOsrConfig = 0x36;
        private const byte RegOdrConfig = 0x37;
        private const byte RegCmd = 0x7E;

        // ISA constants, matching watch_core::elevation.
        private const double BaroScaleM = 44330.0;
        private const double BaroExponent = 0.190295;
        private const double StandardSeaLevelPa = 101325.0;

        // 1600 m — inside the canned fixtures' terrain (see the header note).
        private const long DefaultAltitudeMm = 1_600_000;
    }
}
