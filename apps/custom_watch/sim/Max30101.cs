//
// MAX30101 — Renode model of the optical heart-rate AFE the hr task drives over
// TWISPI0 (I2C address 0x57), runtime-compiled by watch.resc and attached to
// the NRF52840_TWIM model (same pattern as NRF52840_RTC_Overflow /
// SharpMipDisplay / BMP581).
//
// Replaces Max86177.cs on the sim's HR rail per decisions.md § 623: tier 1
// orders a MAX30101, so the ELF the simulator boots talks to one. Unlike its
// predecessor, this model is pinned to a PUBLIC datasheet as well as to the
// driver's expectations — the MAX30101 register map is published, so a
// disagreement between model and datasheet is a defect in one of them rather
// than two guesses agreeing.
//
// Register semantics mirror `drivers/max30101/src/lib.rs`:
//   - plain read-back register file (writes store, reads return);
//   - PART_ID (0xFF) returns 0x15 — the driver refuses to configure anything
//     that answers otherwise, which is how a MAX30102 fitted by mistake is
//     caught before it can stream red-LED counts as a plausible wrong pulse;
//   - MODE_CONFIG (0x09): bit 6 = soft reset (registers to power-on zeroes,
//     FIFO cleared, sampling stops; reads back 0 immediately so the driver's
//     reset poll terminates), bit 7 = shutdown (sampling stops, FIFO freezes,
//     register file RETAINED), bits 2:0 = mode, with 0x07 = multi-LED, the only
//     mode in which the slot registers apply;
//   - FIFO_WR_PTR / OVF_COUNTER / FIFO_RD_PTR (0x04/0x05/0x06) are a real ring:
//     the driver derives its sample count from the pointer pair and detects
//     dropped samples from the overflow counter. Writing zero to the read
//     pointer discards unread samples, which is how the driver flushes;
//   - FIFO_DATA (0x07) pops 3-byte samples, 18-bit counts, **untagged** — this
//     part writes one sample per enabled slot in slot order and labels nothing,
//     so the model emits them in exactly that order and the driver's positional
//     tagging is what has to get it right;
//   - MULTI_LED_SLOT_12 (0x11) low nibble selects slot 1's LED (3 = green) and
//     high nibble slot 2's (0 = none, the dark/ambient read);
//   - LED3_PA (0x0E) is live: the synthesized reflected light scales with the
//     programmed green drive, so the firmware's AGC loop closes end-to-end;
//   - TEMP_CONFIG (0x21) bit 0 runs a one-shot die-temperature conversion
//     (deterministic 33.5 degC into TEMP_INT/TEMP_FRAC, self-clearing).
//
// Waveform — deterministic, derived from the sample index n (a 100 Hz
// LimitTimer on the machine's virtual clock; no wall-clock, no randomness):
//
//   reflected(n) = DcBaseline * pa / 36 + tri(n) * PulseAmplitude * pa / 36
//   slot1(n)     = clamp18(reflected(n) + AmbientLevel)   // green on
//   slot2(n)     = clamp18(AmbientLevel)                  // LED off: bleed only
//
// where pa is the live LED3_PA code (36 = the driver's LED_PA_DEFAULT of 0x24,
// so the defaults below are calibrated at that drive), tri(n) is a triangular
// systolic bump (5 samples up, 15 down) once per PulsePeriodSamples, and
// clamp18 pins at the 18-bit ADC full scale (0x3FFFF) — half the MAX86177's,
// which is the whole reason watch_core::ppg::PpgScale is data.
//
// Monitor knobs (settable mid-run, applied from the next sample):
//   sysbus.twi0.max30101 AmbientLevel 100000    # ambient bleed, both slots
//   sysbus.twi0.max30101 PulseAmplitude 0       # systolic amplitude at pa=36
//   sysbus.twi0.max30101 DcBaseline 250         # reflected DC at pa=36
//   sysbus.twi0.max30101 PulsePeriodSamples 83  # 6000/period BPM (83 ~ 72)
//
// Defaults stage the nominal worn wrist at the 18-bit scale: the counts are
// halved from the MAX86177 model's so the same optical scene is described —
// DC 45k (below the 18-bit AGC's 65k-150k corrected-DC target band, so the
// auto-gain visibly steps up and holds), pulse 2000 counts, ambient 0, ~72 BPM.
//
using System;

using Antmicro.Renode.Core;
using Antmicro.Renode.Logging;
using Antmicro.Renode.Peripherals;
using Antmicro.Renode.Peripherals.I2C;
using Antmicro.Renode.Peripherals.Timers;
using Antmicro.Renode.Time;

namespace Antmicro.Renode.Peripherals.Sensors
{
    public class MAX30101 : II2CPeripheral
    {
        public MAX30101(IMachine machine)
        {
            registers = new byte[256];
            fifo = new uint[FifoDepthSamples];

            AmbientLevel = 0;
            PulseAmplitude = 2000;
            DcBaseline = 45000;
            PulsePeriodSamples = 83;

            frameTimer = new LimitTimer(machine.ClockSource, SampleRateHz, this, "frame", eventEnabled: true, limit: 1);
            frameTimer.LimitReached += OnFrame;

            SoftReset();
        }

        // --- monitor-settable synthesis knobs -------------------------------

        /// Ambient light bleeding into the photodiode, in 18-bit ADC counts.
        /// Added to BOTH slots (common mode), so ambient subtraction cancels it.
        public uint AmbientLevel { get; set; }

        /// Systolic pulse amplitude in counts at the default green drive (0x24);
        /// scales with the programmed drive. 0 = no pulse (off-wrist scene).
        public uint PulseAmplitude { get; set; }

        /// Reflected (LED-derived) DC level in counts at the default green drive
        /// (0x24); scales with the programmed drive.
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
                    while(offset + SampleBytes <= count && Available > 0)
                    {
                        var sample = fifo[readPtr];
                        readPtr = (readPtr + 1) % FifoDepthSamples;
                        result[offset] = (byte)(sample >> 16);
                        result[offset + 1] = (byte)(sample >> 8);
                        result[offset + 2] = (byte)sample;
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

        private int Available => (writePtr + FifoDepthSamples - readPtr) % FifoDepthSamples;

        private byte ReadRegister(byte reg)
        {
            switch(reg)
            {
            case REG_PART_ID:
                return PartId;
            case REG_FIFO_WR_PTR:
                lock(fifo)
                {
                    return (byte)writePtr;
                }
            case REG_FIFO_RD_PTR:
                lock(fifo)
                {
                    return (byte)readPtr;
                }
            case REG_OVF_COUNTER:
                lock(fifo)
                {
                    return overflowCounter;
                }
            default:
                return registers[reg];
            }
        }

        private void WriteRegister(byte reg, byte value)
        {
            switch(reg)
            {
            case REG_MODE_CONFIG:
                if((value & MODE_RESET) != 0)
                {
                    this.Log(LogLevel.Info, "soft reset");
                    SoftReset();
                    return;
                }
                var wasShutdown = shutdown;
                shutdown = (value & MODE_SHUTDOWN) != 0;
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

            // The pointer trio is how the driver flushes. Zeroing the read
            // pointer is what actually discards unread samples; the model
            // honours each write literally so a driver that wrote only some of
            // them would visibly not flush.
            case REG_FIFO_WR_PTR:
                lock(fifo)
                {
                    writePtr = value % FifoDepthSamples;
                }
                break;

            case REG_FIFO_RD_PTR:
                lock(fifo)
                {
                    readPtr = value % FifoDepthSamples;
                }
                break;

            case REG_OVF_COUNTER:
                lock(fifo)
                {
                    overflowCounter = value;
                }
                break;

            case REG_LED3_PA:
                if(registers[reg] != value)
                {
                    this.Log(LogLevel.Info, "green LED drive 0x{0:X2} -> 0x{1:X2}", registers[reg], value);
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
                Array.Clear(fifo, 0, fifo.Length);
                readPtr = 0;
                writePtr = 0;
                overflowCounter = 0;
            }
            shutdown = false;
            regPointer = 0;
            sampleIndex = 0;
            UpdateSampling();
        }

        // --- sample synthesis ------------------------------------------------

        private int EnabledSlots
        {
            get
            {
                var slots = registers[REG_MULTI_LED_SLOT_12];
                var n = 0;
                // Slot 2 counts even when it selects no LED: an empty selection
                // is what makes it the ambient read, not what disables it. A
                // slot is off only when the whole pair register is zero, which
                // is the power-on state.
                if(slots != 0)
                {
                    n = 2;
                }
                return n;
            }
        }

        private void UpdateSampling()
        {
            var active = !shutdown
                && (registers[REG_MODE_CONFIG] & MODE_MASK) == MODE_MULTI_LED
                && EnabledSlots > 0;
            if(frameTimer.Enabled != active)
            {
                this.Log(LogLevel.Debug, "sampling {0}", active ? "started" : "stopped");
                frameTimer.Enabled = active;
            }
        }

        private void OnFrame()
        {
            var pa = registers[REG_LED3_PA];
            var k = (long)(sampleIndex % pulsePeriodSamples);
            sampleIndex++;

            long amp = (long)PulseAmplitude * pa / DefaultPa;
            long pulse = 0;
            if(k < PulseRise)
            {
                pulse = amp * k / PulseRise;
            }
            else if(k < PulseRise + PulseFall)
            {
                pulse = amp * (PulseRise + PulseFall - k) / PulseFall;
            }

            long reflected = (long)DcBaseline * pa / DefaultPa + pulse;
            lock(fifo)
            {
                // One sample per enabled slot, in slot order, every period —
                // and BOTH or NEITHER. A frame written half-way would slip the
                // driver's positional tagging, which is precisely the failure
                // its whole-frame reads exist to prevent, so the model must not
                // be able to produce one.
                if(EnabledSlots == 2)
                {
                    Enqueue(ClampAdc(reflected + AmbientLevel));
                    Enqueue(ClampAdc(AmbientLevel));
                }
            }
        }

        // Callers hold the fifo lock.
        private void Enqueue(uint value)
        {
            var next = (writePtr + 1) % FifoDepthSamples;
            if(next == readPtr)
            {
                // Full: the real part rolls over and counts the loss. The
                // counter saturates rather than wrapping, so a host cannot
                // recover how many samples went missing — which is exactly why
                // the driver resyncs instead of trying to.
                readPtr = (readPtr + 1) % FifoDepthSamples;
                if(overflowCounter < 0x1F)
                {
                    overflowCounter++;
                }
            }
            fifo[writePtr] = value & AdcFullScale;
            writePtr = next;
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
        private readonly uint[] fifo;
        private readonly LimitTimer frameTimer;

        private byte regPointer;
        private bool shutdown;
        private ulong sampleIndex;
        private uint pulsePeriodSamples;
        private int readPtr;
        private int writePtr;
        private byte overflowCounter;

        private const long SampleRateHz = 100;

        private const long PulseRise = 5;
        private const long PulseFall = 15;

        private const int SampleBytes = 3;
        private const int FifoDepthSamples = 32;
        private const uint AdcFullScale = 0x3FFFF;

        /// LED_PA_DEFAULT in the driver — the drive the knob defaults are
        /// calibrated at.
        private const long DefaultPa = 0x24;

        private const byte PartId = 0x15;

        private const byte REG_FIFO_WR_PTR = 0x04;
        private const byte REG_OVF_COUNTER = 0x05;
        private const byte REG_FIFO_RD_PTR = 0x06;
        private const byte REG_FIFO_DATA = 0x07;
        private const byte REG_MODE_CONFIG = 0x09;
        private const byte REG_LED3_PA = 0x0E;
        private const byte REG_MULTI_LED_SLOT_12 = 0x11;
        private const byte REG_TEMP_INT = 0x1F;
        private const byte REG_TEMP_FRAC = 0x20;
        private const byte REG_TEMP_CONFIG = 0x21;
        private const byte REG_PART_ID = 0xFF;

        private const byte MODE_RESET = 1 << 6;
        private const byte MODE_SHUTDOWN = 1 << 7;
        private const byte MODE_MASK = 0x07;
        private const byte MODE_MULTI_LED = 0x07;

        private const byte TEMP_EN = 1 << 0;
    }
}
