//
// NRF52840_Timer_Shorts — the stock Renode NRF52840_Timer model (v1.16.1,
// renode-infrastructure @ add012af) with the SHORTS register implemented.
//
// Why this exists: embassy-nrf's `BufferedUarte` derives its RX ring write
// position from a TIMER used as a byte counter — EVENTS_RXDRDY drives
// TASKS_COUNT over PPI, and the count is bounded by nothing but a shortcut:
//
//     timer.cc(1).write(rx_len as u32 * 2);
//     timer.cc(1).short_compare_clear();
//
// The stock model carries `Shortcuts = 0x200` in its register enum but never
// defines the register, so every SHORTS write is dropped — and every read
// returns 0, which also defeats the read-modify-write embassy does to set the
// bit. The counter then climbs monotonically past 2 * rx_len and
// BufferedUarte's defensive guard (`if rxdrdy > s.rx_buf.len() * 2 { rxdrdy =
// 0 }`) pins the derived write position at 0 permanently, roughly 1 KiB of
// NMEA (~1.07 s at 9600 baud) into a run. On real hardware the shortcut
// exists and none of this happens.
//
// Register layout is from the Nordic-published nRF52840 SVD: SHORTS at 0x200,
// COMPARE[0..5]_CLEAR in bits 0-5, COMPARE[0..5]_STOP in bits 8-13, each
// described as "shortcut between event COMPARE[i] and task CLEAR / STOP".
// Bits 6-7 and 14-31 are reserved. An instance declared with fewer than six
// compare channels reserves the bits its missing channels would own.
//
// Deltas from the upstream model, all marked with "SHORTS:" comments:
//   - SHORTS (0x200) is a real read/write register (was: unmapped);
//   - a compare match applies that channel's shortcuts, in BOTH the clocked
//     path (MODE=Timer) and the TASKS_COUNT path (MODE=Counter /
//     LowPowerCounter — the latter is what BufferedUarte runs on, since
//     embassy's `Timer::new_counter` selects LowPowerCounter);
//   - TASKS_STOP's and TASKS_CLEAR's bodies are named (StopCounter /
//     ClearCounter) and the shortcuts call the same two, so a shortcut and
//     its task cannot drift apart;
//   - the TASKS_COUNT path increments every channel first, then tests every
//     match against the post-increment counter, and only then applies the
//     shortcuts — a CLEAR taken mid-loop would otherwise mask a match on a
//     later channel, or invent one on a channel whose CC happens to be 0.
//
// Everything else is upstream verbatim. With SHORTS == 0 — its reset value,
// and what embassy explicitly writes for every channel it is not shortcutting
// — this model behaves exactly as the stock one. Two upstream gaps are left
// alone deliberately, because nothing here needs either and closing them
// would change what the model publishes: BITMODE (0x508) is unimplemented (the
// inner counters are wider than 32 bits regardless, and the only consumer here
// wraps far below 2^32), and the TASKS_COUNT path sets EVENTS_COMPARE[n]
// without raising the peripheral's PPI event the way the clocked path does —
// so do not build a PPI chain off a compare event in counter mode and expect
// it to fire.
//
// Upstream: renode-infrastructure
// src/Emulator/Peripherals/Peripherals/Timers/NRF52840_Timer.cs
// (Copyright (c) 2010-2025 Antmicro, MIT).
//
using System;

using Antmicro.Renode.Core;
using Antmicro.Renode.Core.Structure.Registers;
using Antmicro.Renode.Exceptions;
using Antmicro.Renode.Logging;
using Antmicro.Renode.Peripherals.Miscellaneous;

namespace Antmicro.Renode.Peripherals.Timers
{
    public class NRF52840_Timer_Shorts : BasicDoubleWordPeripheral, IKnownSize, INRFEventProvider
    {
        public NRF52840_Timer_Shorts(IMachine machine, int numberOfEvents) : base(machine)
        {
            IRQ = new GPIO();

            if(numberOfEvents > MaxNumberOfEvents)
            {
                throw new ConstructionException($"Cannot create {nameof(NRF52840_Timer_Shorts)} with {numberOfEvents} events (must be less than {MaxNumberOfEvents})");
            }
            this.numberOfEvents = numberOfEvents;

            this.eventCompareEnabled = new IFlagRegisterField[numberOfEvents];
            innerTimers = new ComparingTimer[numberOfEvents];
            for(var i = 0u; i < innerTimers.Length; i++)
            {
                var j = i;
                innerTimers[j] = new ComparingTimer(machine.ClockSource, InitialFrequency, this, $"compare{j}", eventEnabled: true);
                innerTimers[j].CompareReached += () =>
                {
                    this.Log(LogLevel.Noisy, "Compare Reached on CC{0} is {1}", j, innerTimers[j].Compare);
                    eventCompareEnabled[j].Value = true;
                    EventTriggered?.Invoke((uint)Register.Compare0EventPending + 0x4u * j);
                    UpdateInterrupts();
                    ApplyShortcuts((int)j); // SHORTS: the clocked path
                };
            }

            DefineRegisters();
        }

        public override void Reset()
        {
            base.Reset();

            foreach(var timer in innerTimers)
            {
                timer.Reset();
            }

            IRQ.Unset();
        }

        public GPIO IRQ { get; }

        public long Size => 0x1000;

        public event Action<uint> EventTriggered;

        private void DefineRegisters()
        {
            Register.Start.Define(this)
                .WithFlag(0, FieldMode.Write, name: "TASKS_START", writeCallback: (_, value) =>
                {
                    if(value)
                    {
                        timerRunning = true;
                        if(mode.Value == Mode.Timer)
                        {
                            foreach(var timer in innerTimers)
                            {
                                timer.Enabled = true;
                            }
                        }
                    }
                })
                .WithReservedBits(1, 31)
            ;

            Register.Stop.Define(this)
                .WithFlag(0, FieldMode.Write, name: "TASKS_STOP", writeCallback: (_, value) =>
                {
                    if(value)
                    {
                        StopCounter();
                    }
                })
                .WithReservedBits(1, 31)
            ;

            Register.Count.Define(this)
                .WithFlag(0, FieldMode.Write, name: "TASK_COUNT", writeCallback: (_, value) =>
                {
                    if(value)
                    {
                        if(!timerRunning)
                        {
                            this.Log(LogLevel.Warning, "Triggered TASK_COUNT before issuing TASK_START, ignoring...");
                            return;
                        }
                        if(mode.Value == Mode.Timer)
                        {
                            this.Log(LogLevel.Warning, "Triggered TASK_COUNT in TIMER mode, ignoring...");
                            return;
                        }
                        foreach(var timer in innerTimers)
                        {
                            timer.Value++;
                        }
                        // SHORTS: every channel is tested against the
                        // post-increment counter before any shortcut runs, and
                        // the shortcut then takes effect within this same
                        // TASKS_COUNT — a CLEAR that lands one count late
                        // reproduces exactly the runaway counter this model
                        // exists to fix.
                        var stop = false;
                        var clear = false;
                        for(var i = 0; i < numberOfEvents; i++)
                        {
                            if(innerTimers[i].Compare != innerTimers[i].Value)
                            {
                                continue;
                            }
                            eventCompareEnabled[i].Value = true;
                            UpdateInterrupts();
                            stop |= shortCompareStop[i].Value;
                            clear |= shortCompareClear[i].Value;
                        }
                        if(stop)
                        {
                            StopCounter();
                        }
                        if(clear)
                        {
                            ClearCounter();
                        }
                    }
                })
                .WithReservedBits(1, 31)
            ;

            Register.Clear.Define(this)
                .WithFlag(0, FieldMode.Write, name: "TASK_CLEAR", writeCallback: (_, value) =>
                {
                    if(value)
                    {
                        ClearCounter();
                    }
                })
                .WithReservedBits(1, 31)
            ;

            Register.Capture0.DefineMany(this, (uint)numberOfEvents, setup: (register, idx) =>
            {
                register
                    .WithFlag(0, FieldMode.Write, name: "TASKS_CAPTURE", writeCallback: (_, __) =>
                    {
                        SetCompare(idx, innerTimers[idx].Value);
                    })
                    .WithReservedBits(1, 31);
            });

            Register.Compare0EventPending.DefineMany(this, (uint)numberOfEvents, setup: (register, idx) =>
            {
                register
                    .WithFlag(0, out eventCompareEnabled[idx], name: $"EVENTS_COMPARE[{idx}]", writeCallback: (_, __) =>
                    {
                        UpdateInterrupts();
                    })
                    .WithReservedBits(1, 31);
            });

            // SHORTS: was unmapped upstream, so every write was dropped and
            // every read came back 0.
            Register.Shortcuts.Define(this)
                .WithFlags(0, numberOfEvents, out shortCompareClear, name: "COMPARE_CLEAR")
                .WithReservedBits(numberOfEvents, 8 - numberOfEvents)
                .WithFlags(8, numberOfEvents, out shortCompareStop, name: "COMPARE_STOP")
                .WithReservedBits(8 + numberOfEvents, 24 - numberOfEvents)
            ;

            Register.InterruptEnableSet.Define(this)
                .WithReservedBits(0, 16)
                .WithFlags(16, numberOfEvents, out eventCompareInterruptEnabled, FieldMode.Set | FieldMode.Read, name: "COMPARE")
                .WithReservedBits(22 - MaxNumberOfEvents + numberOfEvents, 10 + MaxNumberOfEvents - numberOfEvents)
                .WithChangeCallback((_, __) =>
                {
                    UpdateInterrupts();
                })
            ;

            Register.InterruptEnableClear.Define(this)
                .WithReservedBits(0, 16)
                .WithFlags(16, numberOfEvents, name: "COMPARE", writeCallback: (i, _, value) => { if(value) eventCompareInterruptEnabled[i].Value = false; })
                .WithReservedBits(22 - MaxNumberOfEvents + numberOfEvents, 10 + MaxNumberOfEvents - numberOfEvents)
                .WithChangeCallback((_, __) =>
                {
                    UpdateInterrupts();
                })
            ;

            Register.Mode.Define(this)
                .WithEnumField(0, 2, out mode, name: "MODE", changeCallback: (_, value) =>
                {
                    if(value != Mode.Timer && innerTimers[0].Enabled)
                    {
                        this.Log(LogLevel.Error, "Switching timer to COUNTER mode while the timer is running");
                    }
                })
            ;

            Register.Prescaler.Define(this)
                .WithValueField(0, 4, out prescaler, name: "PRESCALER", writeCallback: (_, value) =>
                {
                    foreach(var timer in innerTimers)
                    {
                        timer.Divider = (uint)(1 << (int)value);
                    }
                })
                .WithReservedBits(12, 20)
            ;

            Register.Compare0.DefineMany(this, (uint)numberOfEvents, setup: (register, idx) =>
            {
                register
                    .WithValueField(0, 32, name: "CAPTURE_COMPARE", writeCallback: (_, value) =>
                    {
                        SetCompare(idx, value);
                    },
                    valueProviderCallback: _ =>
                    {
                        return (uint)innerTimers[idx].Compare;
                    });
            });
        }

        // SHORTS: a compare match on `idx` triggers whichever of the STOP and
        // CLEAR tasks that channel is shortcutted to. Same two helpers the
        // TASKS_STOP / TASKS_CLEAR registers call, because on the device the
        // shortcut IS that task.
        private void ApplyShortcuts(int idx)
        {
            if(shortCompareStop[idx].Value)
            {
                StopCounter();
            }
            if(shortCompareClear[idx].Value)
            {
                ClearCounter();
            }
        }

        private void StopCounter()
        {
            timerRunning = false;
            foreach(var timer in innerTimers)
            {
                timer.Enabled = false;
            }
        }

        private void ClearCounter()
        {
            foreach(var timer in innerTimers)
            {
                timer.Value = 0;
            }
        }

        private void SetCompare(int idx, ulong value)
        {
            eventCompareEnabled[idx].Value = false;
            UpdateInterrupts();
            innerTimers[idx].Compare = value;
        }

        private void UpdateInterrupts()
        {
            var flag = false;

            for(var i = 0; i < numberOfEvents; i++)
            {
                flag |= eventCompareInterruptEnabled[i].Value && eventCompareEnabled[i].Value;
            }

            IRQ.Set(flag);
        }

        private IFlagRegisterField[] eventCompareInterruptEnabled;
        private IValueRegisterField prescaler;
        private IEnumRegisterField<Mode> mode;
        private bool timerRunning;

        // SHORTS: one CLEAR flag and one STOP flag per compare channel.
        private IFlagRegisterField[] shortCompareClear;
        private IFlagRegisterField[] shortCompareStop;

        private readonly IFlagRegisterField[] eventCompareEnabled;

        private readonly ComparingTimer[] innerTimers;

        private readonly int numberOfEvents;
        private const int InitialFrequency = 16000000;
        private const int MaxNumberOfEvents = 6;

        private enum Mode
        {
            Timer,
            Counter,
            LowPowerCounter
        }

        private enum Register : long
        {
            Start = 0x000,
            Stop = 0x004,
            Count = 0x008,
            Clear = 0x00C,
            Shutdown = 0x010,

            Capture0 = 0x040,
            Capture1 = 0x044,
            Capture2 = 0x048,
            Capture3 = 0x04C,
            Capture4 = 0x050,
            Capture5 = 0x054,

            Compare0EventPending = 0x140,
            Compare1EventPending = 0x144,
            Compare2EventPending = 0x148,
            Compare3EventPending = 0x14C,
            Compare4EventPending = 0x150,
            Compare5EventPending = 0x154,

            Shortcuts = 0x200,

            InterruptEnableSet = 0x304,
            InterruptEnableClear = 0x308,

            Mode = 0x504,
            BitMode = 0x508,
            Prescaler = 0x510,

            Compare0 = 0x540,
            Compare1 = 0x544,
            Compare2 = 0x548,
            Compare3 = 0x54C,
            Compare4 = 0x550,
            Compare5 = 0x554
        }
    }
}
