//
// MAX86177 — Renode model of the Maxim optical heart-rate AFE the hr task
// drives over TWISPI0 (I2C address 0x62), runtime-compiled by watch.resc and
// attached to the NRF52840_TWIM model (same pattern as NRF52840_RTC_Overflow /
// SharpMipDisplay).
//
// Register semantics mirror what `drivers/max86177/src/lib.rs` programs — the
// register map there is itself a bench-verify target against the real
// datasheet, so this model is deliberately pinned to the DRIVER's expectations
// (the pinned init-sequence host test), not to a datasheet the driver hasn't
// been verified against either:
//   - plain read-back register file (writes store, reads return — the init
//     sequence including the MEAS2 dark-slot block reads back verbatim);
//   - SYSTEM_CONFIG_1: bit 0 = soft reset (registers to power-on zeroes, FIFO
//     cleared, sampling stops; the bit reads back 0 immediately — the driver's
//     reset poll sees it self-cleared), bit 1 = shutdown (sampling stops, FIFO
//     freezes, register file RETAINED — the firmware's duty-cycle wake relies
//     on config surviving shutdown; that retention is a datasheet assumption
//     the firmware's host tests document as a bench-verify target, and this
//     model honours it deliberately);
//   - FIFO_CONFIG_2 bit 4 = FIFO flush (self-clearing), bit 1 = rollover;
//   - MEAS_ENABLE bits 0/1 gate the MEAS1 (LED-on PPG) / MEAS2 (LED-off
//     ambient) slots; sampling runs only when enabled and not shut down;
//   - FIFO_COUNTER returns the word count; FIFO_DATA pops 3-byte words tagged
//     MEAS1 (0x01) / MEAS2 (0x02) in the 5 bits above the 19-bit count;
//   - MEAS1_LEDA_CURRENT is live: the synthesized reflected light scales with
//     the programmed drive, so the firmware's AGC loop closes end-to-end;
//   - TEMP_CONFIG bit 0 runs a one-shot die-temperature conversion
//     (deterministic 33.5 degC into TEMP_INT/TEMP_FRAC, self-clearing).
//
// Waveform — deterministic, derived from the sample index n (a 100 Hz
// LimitTimer on the machine's virtual clock; no wall-clock, no randomness):
//
//   reflected(n) = DcBaseline * pa / 64 + tri(n) * PulseAmplitude * pa / 64
//   MEAS1(n)     = clamp19(reflected(n) + AmbientLevel)   // LED on: pulse + bleed
//   MEAS2(n)     = clamp19(AmbientLevel)                  // LED off: bleed only
//
// where pa is the live LEDA_CURRENT code (64 = the driver's LED_PA_DEFAULT,
// so the defaults below are calibrated at that drive), tri(n) is a triangular
// systolic bump (5 samples up, 15 down) once per PulsePeriodSamples, and
// clamp19 pins at the 19-bit ADC full scale (0x7FFFF) — pushing AmbientLevel
// toward the rail clips MEAS1 exactly like a real converter would.
//
// Monitor knobs (settable mid-run, applied from the next sample):
//   sysbus.twi0.max86177 AmbientLevel 200000    # ambient bleed, both slots
//   sysbus.twi0.max86177 PulseAmplitude 0       # systolic amplitude at pa=64
//   sysbus.twi0.max86177 DcBaseline 500         # reflected DC at pa=64
//   sysbus.twi0.max86177 PulsePeriodSamples 83  # 6000/period BPM (83 ~ 72)
//
// Defaults stage the nominal worn wrist: DC 90k (below the AGC's 130k-300k
// corrected-DC target band, so the auto-gain visibly steps 0x40 -> 0x60 and
// holds), pulse 4000 counts, ambient 0, ~72 BPM.
//
using System;
using System.Collections.Generic;

using Antmicro.Renode.Core;
using Antmicro.Renode.Logging;
using Antmicro.Renode.Peripherals;
using Antmicro.Renode.Peripherals.I2C;
using Antmicro.Renode.Peripherals.Timers;
using Antmicro.Renode.Time;

namespace Antmicro.Renode.Peripherals.Sensors
{
    public class MAX86177 : II2CPeripheral
    {
        public MAX86177(IMachine machine)
        {
            registers = new byte[256];
            fifo = new Queue<uint>();

            AmbientLevel = 0;
            PulseAmplitude = 4000;
            DcBaseline = 90000;
            PulsePeriodSamples = 83;

            frameTimer = new LimitTimer(machine.ClockSource, SampleRateHz, this, "frame", eventEnabled: true, limit: 1);
            frameTimer.LimitReached += OnFrame;

            SoftReset();
        }

        // --- monitor-settable synthesis knobs -------------------------------

        /// Ambient light bleeding into the photodiode, in 19-bit ADC counts.
        /// Added to BOTH slots (common mode), so ambient subtraction cancels it.
        public uint AmbientLevel { get; set; }

        /// Systolic pulse amplitude in counts at the default LED drive (0x40);
        /// scales with the programmed drive. 0 = no pulse (off-wrist scene).
        public uint PulseAmplitude { get; set; }

        /// Reflected (LED-derived) DC level in counts at the default LED drive
        /// (0x40); scales with the programmed drive.
        public uint DcBaseline { get; set; }

        /// Samples per synthetic beat at the 100 Hz frame rate: BPM = 6000 /
        /// period. The default 83 gives ~72.3 BPM.
        public uint PulsePeriodSamples
        {
            get => pulsePeriodSamples;
            set => pulsePeriodSamples = Math.Max(1u, value);
        }

        // --- II2CPeripheral --------------------------------------------------

        public void Reset()
        {
            SoftReset();
        }

        public void Write(byte[] data)
        {
            if(data.Length == 0)
            {
                return;
            }
            regPointer = data[0];
            for(var i = 1; i < data.Length; i++)
            {
                WriteRegister((byte)(regPointer + i - 1), data[i]);
            }
        }

        public byte[] Read(int count = 1)
        {
            var result = new byte[count];
            if(regPointer == REG_FIFO_DATA)
            {
                lock(fifo)
                {
                    var offset = 0;
                    while(offset + SampleBytes <= count && fifo.Count > 0)
                    {
                        var word = fifo.Dequeue();
                        result[offset] = (byte)(word >> 16);
                        result[offset + 1] = (byte)(word >> 8);
                        result[offset + 2] = (byte)word;
                        offset += SampleBytes;
                    }
                }
                return result;
            }
            for(var i = 0; i < count; i++)
            {
                result[i] = ReadRegister((byte)(regPointer + i));
            }
            return result;
        }

        public void FinishTransmission()
        {
            // The register pointer persists across transactions, like the real
            // part: a write of [reg] followed by a read in a later transaction
            // still reads `reg`.
        }

        // --- register file ---------------------------------------------------

        private byte ReadRegister(byte reg)
        {
            if(reg == REG_FIFO_COUNTER)
            {
                lock(fifo)
                {
                    return (byte)Math.Min(fifo.Count, 255);
                }
            }
            return registers[reg];
        }

        private void WriteRegister(byte reg, byte value)
        {
            switch(reg)
            {
            case REG_SYSTEM_CONFIG_1:
                if((value & SW_RESET) != 0)
                {
                    this.Log(LogLevel.Info, "soft reset");
                    SoftReset();
                    return;
                }
                var wasShutdown = shutdown;
                shutdown = (value & SHUTDOWN) != 0;
                registers[reg] = value;
                if(shutdown && !wasShutdown)
                {
                    this.Log(LogLevel.Info, "shut down — sampling stopped, FIFO frozen, registers retained");
                }
                else if(!shutdown && wasShutdown)
                {
                    this.Log(LogLevel.Info, "woken — sampling resumes from retained config");
                }
                UpdateSampling();
                break;

            case REG_FIFO_CONFIG_2:
                if((value & FIFO_FLUSH) != 0)
                {
                    lock(fifo)
                    {
                        this.Log(LogLevel.Info, "FIFO flushed ({0} word(s) dropped)", fifo.Count);
                        fifo.Clear();
                    }
                }
                // The flush bit self-clears.
                registers[reg] = (byte)(value & ~FIFO_FLUSH);
                break;

            case REG_MEAS_ENABLE:
                registers[reg] = value;
                UpdateSampling();
                break;

            case REG_MEAS1_LEDA_CURRENT:
                if(registers[reg] != value)
                {
                    this.Log(LogLevel.Info, "LED drive 0x{0:X2} -> 0x{1:X2}", registers[reg], value);
                }
                registers[reg] = value;
                break;

            case REG_TEMP_CONFIG:
                if((value & TEMP_EN) != 0)
                {
                    // One-shot conversion, completed instantly: a fixed,
                    // deterministic 33.5 degC (wrist-adjacent die temperature).
                    registers[REG_TEMP_INT] = 33;
                    registers[REG_TEMP_FRAC] = 0x08;
                }
                // The enable bit self-clears once the result latches.
                registers[reg] = (byte)(value & ~TEMP_EN);
                break;

            default:
                registers[reg] = value;
                break;
            }
        }

        private void SoftReset()
        {
            Array.Clear(registers, 0, registers.Length);
            lock(fifo)
            {
                fifo.Clear();
            }
            shutdown = false;
            regPointer = 0;
            sampleIndex = 0;
            UpdateSampling();
        }

        // --- sample synthesis ------------------------------------------------

        private void UpdateSampling()
        {
            var active = !shutdown && (registers[REG_MEAS_ENABLE] & (MEAS1_ENABLE | MEAS2_ENABLE)) != 0;
            if(frameTimer.Enabled != active)
            {
                this.Log(LogLevel.Debug, "sampling {0}", active ? "started" : "stopped");
                frameTimer.Enabled = active;
            }
        }

        private void OnFrame()
        {
            var pa = registers[REG_MEAS1_LEDA_CURRENT];
            var k = (long)(sampleIndex % pulsePeriodSamples);
            sampleIndex++;

            long amp = (long)PulseAmplitude * pa / 64;
            long pulse = 0;
            if(k < PulseRise)
            {
                pulse = amp * k / PulseRise;
            }
            else if(k < PulseRise + PulseFall)
            {
                pulse = amp * (PulseRise + PulseFall - k) / PulseFall;
            }

            long reflected = (long)DcBaseline * pa / 64 + pulse;
            var enable = registers[REG_MEAS_ENABLE];
            lock(fifo)
            {
                if((enable & MEAS1_ENABLE) != 0)
                {
                    EnqueueWord(MEAS1_TAG, ClampAdc(reflected + AmbientLevel));
                }
                if((enable & MEAS2_ENABLE) != 0)
                {
                    EnqueueWord(MEAS2_TAG, ClampAdc(AmbientLevel));
                }
            }
        }

        // Callers hold the fifo lock.
        private void EnqueueWord(uint tag, uint value)
        {
            if(fifo.Count >= FifoCapacityWords)
            {
                if((registers[REG_FIFO_CONFIG_2] & FIFO_ROLLOVER) != 0)
                {
                    fifo.Dequeue();
                }
                else
                {
                    return;
                }
            }
            fifo.Enqueue((tag << 19) | (value & AdcFullScale));
        }

        private static uint ClampAdc(long value)
        {
            if(value < 0)
            {
                return 0;
            }
            if(value > AdcFullScale)
            {
                return AdcFullScale;
            }
            return (uint)value;
        }

        private readonly byte[] registers;
        private readonly Queue<uint> fifo;
        private readonly LimitTimer frameTimer;

        private byte regPointer;
        private bool shutdown;
        private ulong sampleIndex;
        private uint pulsePeriodSamples;

        // Matches the 100 Hz output rate the driver configures (and the
        // SAMPLE_RATE_HZ the hr task hands the peak detector).
        private const long SampleRateHz = 100;

        // Systolic bump shape, in samples: sharp upstroke, slower decay.
        private const long PulseRise = 5;
        private const long PulseFall = 15;

        private const int SampleBytes = 3;
        private const int FifoCapacityWords = 256;
        private const uint AdcFullScale = 0x7FFFF;
        private const uint MEAS1_TAG = 0x01;
        private const uint MEAS2_TAG = 0x02;

        private const byte REG_FIFO_COUNTER = 0x0B;
        private const byte REG_FIFO_DATA = 0x0C;
        private const byte REG_FIFO_CONFIG_2 = 0x0E;
        private const byte REG_SYSTEM_CONFIG_1 = 0x10;
        private const byte REG_MEAS_ENABLE = 0x13;
        private const byte REG_MEAS1_LEDA_CURRENT = 0x19;
        private const byte REG_TEMP_CONFIG = 0x20;
        private const byte REG_TEMP_INT = 0x21;
        private const byte REG_TEMP_FRAC = 0x22;

        private const byte SW_RESET = 1 << 0;
        private const byte SHUTDOWN = 1 << 1;
        private const byte FIFO_FLUSH = 1 << 4;
        private const byte FIFO_ROLLOVER = 1 << 1;
        private const byte MEAS1_ENABLE = 1 << 0;
        private const byte MEAS2_ENABLE = 1 << 1;
        private const byte TEMP_EN = 1 << 0;
    }
}
