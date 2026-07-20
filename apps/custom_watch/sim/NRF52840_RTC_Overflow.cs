//
// NRF52840_RTC_Overflow — the stock Renode NRF52840_RTC model (v1.16.1,
// renode-infrastructure @ add012af) with a real OVRFLW event.
//
// Why this exists: the firmware's embassy-nrf time driver extends RTC1's
// 24-bit counter to a 64-bit monotonic Instant by counting half-periods —
// COMPARE[3] at 0x800000 plus the OVRFLW event at the wrap each bump a period
// counter. The stock Renode model breaks BOTH legs:
//
//   1. `platforms/cpus/nrf52840.repl` declares rtc1 with `numberOfEvents: 3`,
//      but the real nRF52840 RTC1 has FOUR compare channels — so the CC[3]
//      write and its compare event are silently dropped (sim/watch.resc
//      re-registers rtc1 with numberOfEvents: 4 to fix that half);
//   2. the model's OVRFLW is a tagged (log-only) flag — the event never fires
//      (this file fixes that half).
//
// With neither firing, Instant::now() wraps to zero every 2^24 ticks at
// 32768 Hz = 512 s: every uptime-anchored path (the recorder's fix
// acceptance, moving time, alerts, staleness budgets) froze 8.5 minutes into
// a sim run. On real hardware both events exist and none of this happens.
//
// Deltas from the upstream model, all marked with "OVRFLW:" comments:
//   - EVENTS_OVRFLW (0x104) is a real event register (was: unmapped);
//   - INTENSET/INTENCLR bit 1 is a real interrupt-enable flag (was: tagged);
//   - EVTEN/EVTENSET/EVTENCLR bit 1 is a real PPI-event-enable flag;
//   - a LimitTimer fires the event once per counter period, phase-locked to
//     the compare timers (same clock source, divider, start/stop/clear);
//   - TASKS_TRIGOVRFLW (0x00C) is implemented (counter := 0xFFFFF0);
//   - UpdateTimersEnable guards the nullable `tick` (the stock code throws
//     on TASKS_STOP with the tick interrupt unconfigured).
//
// Upstream: renode-infrastructure
// src/Emulator/Peripherals/Peripherals/Timers/NRF52840_RTC.cs (MIT).
//
using System;
using System.Collections.Generic;

using Antmicro.Renode.Core;
using Antmicro.Renode.Core.Structure.Registers;
using Antmicro.Renode.Exceptions;
using Antmicro.Renode.Logging;
using Antmicro.Renode.Peripherals.Bus;
using Antmicro.Renode.Peripherals.Miscellaneous;
using Antmicro.Renode.Time;

namespace Antmicro.Renode.Peripherals.Timers
{
    public class NRF52840_RTC_Overflow : IDoubleWordPeripheral, IKnownSize, INRFEventProvider
    {
        public NRF52840_RTC_Overflow(IMachine machine, int numberOfEvents)
        {
            IRQ = new GPIO();

            if(numberOfEvents > MaxNumberOfEvents)
            {
                throw new ConstructionException($"Cannot create {nameof(NRF52840_RTC_Overflow)} with {numberOfEvents} events (must be less than {MaxNumberOfEvents})");
            }
            this.numberOfEvents = numberOfEvents;
            compareEventEnabled = new IFlagRegisterField[numberOfEvents];
            compareReached = new IFlagRegisterField[numberOfEvents];
            compareInterruptEnabled = new IFlagRegisterField[numberOfEvents];

            innerTimers = new ComparingTimer[numberOfEvents];
            for(var i = 0u; i < innerTimers.Length; i++)
            {
                var j = i;
                // counters are 24-bits
                innerTimers[i] = new ComparingTimer(machine.ClockSource, InitialFrequency, this, $"compare{i}", eventEnabled: true, limit: CounterPeriod, compare: CounterPeriod);
                innerTimers[i].CompareReached += () =>
                {
                    this.Log(LogLevel.Noisy, "IRQ #{0} triggered", j);
                    compareReached[j].Value = true;
                    if(compareEventEnabled[j].Value)
                    {
                        EventTriggered?.Invoke((uint)Register.Compare0EventPending + j * 4);
                    }
                    UpdateInterrupts();
                };
            }

            // OVRFLW: fires once per counter period, in phase with the compare
            // timers above — same clock source and initial frequency, and the
            // same limit the ComparingTimer wraps its accumulated value at, so
            // the event lands exactly when COUNTER returns to zero. Direction
            // must be Ascending: the timer's Value then mirrors the counter
            // (0 → fire at the wrap), so TASKS_CLEAR's `Value = 0` restarts a
            // full period instead of landing on the Descending fire-point and
            // faking an overflow at boot.
            overflowTimer = new LimitTimer(machine.ClockSource, InitialFrequency, this, "overflow", eventEnabled: true, limit: CounterPeriod, direction: Direction.Ascending);
            overflowTimer.LimitReached += () =>
            {
                this.Log(LogLevel.Noisy, "OVRFLW triggered");
                overflowPending.Value = true;
                if(overflowEventEnabled.Value)
                {
                    EventTriggered?.Invoke((uint)Register.Overflow);
                }
                UpdateInterrupts();
            };

            tickTimer = new LimitTimer(machine.ClockSource, InitialFrequency, this, "tick", eventEnabled: true, limit: 0x1);
            tickTimer.LimitReached += () =>
            {
                tickEvent.Value = true;
                UpdateInterrupts();
            };

            DefineRegisters();
        }

        public uint ReadDoubleWord(long offset)
        {
            return registers.Read(offset);
        }

        public void WriteDoubleWord(long offset, uint value)
        {
            registers.Write(offset, value);
        }

        public void Reset()
        {
            registers.Reset();
            foreach(var timer in innerTimers)
            {
                timer.Reset();
            }
            overflowTimer.Reset(); // OVRFLW
            tickTimer.Reset();
            IRQ.Unset();
        }

        public GPIO IRQ { get; }

        public long Size => 0x1000;

        public event Action<uint> EventTriggered;

        private void UpdateTimersEnable(bool? global = null, bool? tick = null)
        {
            if(global.HasValue)
            {
                foreach(var timer in innerTimers)
                {
                    timer.Enabled = global.Value;
                }
                overflowTimer.Enabled = global.Value; // OVRFLW: runs with the counter
            }

            // due to optimization reasons we try to keep
            // the tick timer disabled as long as possible
            // - we enable it only when the global timer is
            // enabled and the tick event is unmasked
            if(tick.HasValue || (global.HasValue && !global.Value))
            {
                // OVRFLW delta: `tick` may be null on the TASKS_STOP path —
                // fall back to the current tick-interrupt mask instead of
                // throwing on Nullable.Value.
                tickTimer.Enabled = innerTimers[0].Enabled && (tick ?? tickInterruptEnabled.Value);
            }
        }

        private void DefineRegisters()
        {
            var registersMap = new Dictionary<long, DoubleWordRegister>
            {
                {(long)Register.Start, new DoubleWordRegister(this)
                    .WithFlag(0, FieldMode.Write, name: "TASKS_START", writeCallback: (_, value) =>
                    {
                        if(value)
                        {
                            UpdateTimersEnable(global: true);
                        }
                    })
                    .WithReservedBits(1, 31)
                },
                {(long)Register.Stop, new DoubleWordRegister(this)
                    .WithFlag(0, FieldMode.Write, name: "TASKS_STOP", writeCallback: (_, value) =>
                    {
                        if(value)
                        {
                            UpdateTimersEnable(global: false);
                        }
                    })
                    .WithReservedBits(1, 31)
                },
                {(long)Register.Clear, new DoubleWordRegister(this)
                    .WithFlag(0, FieldMode.Write, name: "TASKS_CLEAR", writeCallback: (_, value) =>
                    {
                        if(value)
                        {
                            foreach(var timer in innerTimers)
                            {
                                timer.Value = 0;
                            }
                            overflowTimer.Value = 0; // OVRFLW: stay in phase
                            tickTimer.Value = 0;
                        }
                    })
                    .WithReservedBits(1, 31)
                },
                {(long)Register.TriggerOverflow, new DoubleWordRegister(this)
                    // OVRFLW: TASKS_TRIGOVRFLW sets the counter to 0xFFFFF0
                    // (nRF52840 PS §24.3), so the overflow event fires 16
                    // ticks later through the normal wrap path.
                    .WithFlag(0, FieldMode.Write, name: "TASKS_TRIGOVRFLW", writeCallback: (_, value) =>
                    {
                        if(value)
                        {
                            foreach(var timer in innerTimers)
                            {
                                timer.Value = 0xFFFFF0;
                            }
                            overflowTimer.Value = 0xFFFFF0;
                        }
                    })
                    .WithReservedBits(1, 31)
                },
                {(long)Register.InterruptEnableSet, new DoubleWordRegister(this)
                    .WithFlag(0, out tickInterruptEnabled, FieldMode.Set | FieldMode.Read, name: "TICK")
                    .WithFlag(1, out overflowInterruptEnabled, FieldMode.Set | FieldMode.Read, name: "OVRFLW") // OVRFLW: was tagged
                    .WithReservedBits(2, 14)
                    .WithFlags(16, numberOfEvents, out compareInterruptEnabled, FieldMode.Set | FieldMode.Read, name: "COMPARE")
                    .WithChangeCallback((_, __) =>
                    {
                        UpdateTimersEnable(tick: tickInterruptEnabled.Value);
                        UpdateInterrupts();
                    })
                },
                {(long)Register.InterruptEnableClear, new DoubleWordRegister(this)
                    .WithFlag(0, name: "TICK",
                          writeCallback: (_, value) => tickInterruptEnabled.Value &= !value,
                          valueProviderCallback: _ => tickInterruptEnabled.Value)
                    .WithFlag(1, name: "OVRFLW", // OVRFLW: was tagged
                          writeCallback: (_, value) => overflowInterruptEnabled.Value &= !value,
                          valueProviderCallback: _ => overflowInterruptEnabled.Value)
                    .WithReservedBits(2, 14)
                    .WithFlags(16, numberOfEvents, name: "COMPARE",
                          writeCallback: (j, _, value) => compareInterruptEnabled[j].Value &= !value,
                          valueProviderCallback: (j, value) => compareInterruptEnabled[j].Value)
                    //missing register fields defined below
                    .WithChangeCallback((_, __) =>
                    {
                        UpdateTimersEnable(tick: tickInterruptEnabled.Value);
                        UpdateInterrupts();
                    })
                },
                {(long)Register.Counter, new DoubleWordRegister(this)
                    .WithValueField(0, 24, FieldMode.Read, name: "COUNTER", valueProviderCallback: _ =>
                    {
                        // all timers have the same value, so let's just pick the first one
                        return (uint)innerTimers[0].Value;
                    })
                    .WithReservedBits(24, 8)
                },
                {(long)Register.Prescaler, new DoubleWordRegister(this)
                    .WithValueField(0, 12, out prescaler, name: "PRESCALER", writeCallback: (_, value) =>
                    {
                        foreach(var timer in innerTimers)
                        {
                            timer.Divider = value + 1;
                        }
                        overflowTimer.Divider = value + 1; // OVRFLW: stay in phase
                        tickTimer.Divider = value + 1;
                    })
                    .WithReservedBits(12, 20)
                },
                {(long)Register.EventEnable, new DoubleWordRegister(this)
                   .WithFlag(1, out overflowEventEnabled, name: "OVRFLW") // OVRFLW
                   .WithFlags(16, numberOfEvents, out compareEventEnabled, name: "COMPARE")
                },
                {(long)Register.EventSet, new DoubleWordRegister(this)
                   .WithTaggedFlag("TICK", 0)
                   .WithFlag(1, name: "OVRFLW", // OVRFLW: was tagged
                         writeCallback: (_, val) => overflowEventEnabled.Value |= val,
                         valueProviderCallback: _ => overflowEventEnabled.Value)
                   .WithReservedBits(2, 14)
                   .WithFlags(16, numberOfEvents,
                         writeCallback: (i, _, val) => compareEventEnabled[i].Value |= val,
                         valueProviderCallback: (i, _) => compareEventEnabled[i].Value)
                },
                {(long)Register.EventClear, new DoubleWordRegister(this)
                   .WithFlag(1, name: "OVRFLW", // OVRFLW
                         writeCallback: (_, val) => overflowEventEnabled.Value &= !val,
                         valueProviderCallback: _ => overflowEventEnabled.Value)
                   .WithFlags(16, numberOfEvents,
                         writeCallback: (i, _, val) => compareEventEnabled[i].Value &= !val,
                         valueProviderCallback: (i, _) => compareEventEnabled[i].Value)
                },
                {(long)Register.Tick, new DoubleWordRegister(this)
                   .WithFlag(0, out tickEvent, name: "EVENTS_TICK")
                   .WithReservedBits(1, 31)
                   .WithWriteCallback((_, __) => UpdateInterrupts())
                },
                {(long)Register.Overflow, new DoubleWordRegister(this)
                   // OVRFLW: a real event register — software clears it by
                   // writing 0, exactly like EVENTS_COMPARE[n].
                   .WithFlag(0, out overflowPending, name: "EVENTS_OVRFLW")
                   .WithReservedBits(1, 31)
                   .WithWriteCallback((_, __) => UpdateInterrupts())
                }
            };

            for(var i = 0; i < numberOfEvents; i++)
            {
                var j = i;
                registersMap.Add((long)Register.Compare0 + j * 4, new DoubleWordRegister(this)
                    .WithValueField(0, 24, name: $"COMPARE[{j}]", writeCallback: (_, value) =>
                    {
                        compareReached[j].Value = false;
                        UpdateInterrupts();
                        innerTimers[j].Compare = value;
                    },
                    valueProviderCallback: _ =>
                    {
                        return (uint)innerTimers[j].Compare;
                    })
                    .WithReservedBits(24, 8)
                );

                registersMap.Add((long)Register.Compare0EventPending + j * 4, new DoubleWordRegister(this)
                    .WithFlag(0, out compareReached[j], name: $"EVENTS_COMPARE[{j}]", writeCallback: (_, __) =>
                    {
                        UpdateInterrupts();
                    })
                    .WithReservedBits(1, 31)
                );
            }

            registers = new DoubleWordRegisterCollection(this, registersMap);
        }

        private void UpdateInterrupts()
        {
            var flag = false;

            for(var i = 0; i < numberOfEvents; i++)
            {
                var thisEventSet = compareInterruptEnabled[i].Value && compareReached[i].Value;
                if(thisEventSet)
                {
                    this.Log(LogLevel.Noisy, "Interrupt set by CC{0} interruptEnable={1} compareSet={2} compareEventEnable={3}",
                          i, compareInterruptEnabled[i].Value, compareReached[i].Value, compareEventEnabled[i].Value);
                }
                flag |= thisEventSet;
            }

            flag |= overflowPending.Value && overflowInterruptEnabled.Value; // OVRFLW
            flag |= tickEvent.Value && tickInterruptEnabled.Value;
            IRQ.Set(flag);
        }

        private IFlagRegisterField[] compareInterruptEnabled;
        private IValueRegisterField prescaler;
        private IFlagRegisterField tickInterruptEnabled;
        private IFlagRegisterField tickEvent;
        private IFlagRegisterField overflowInterruptEnabled; // OVRFLW
        private IFlagRegisterField overflowPending;          // OVRFLW
        private IFlagRegisterField overflowEventEnabled;     // OVRFLW

        private DoubleWordRegisterCollection registers;
        private IFlagRegisterField[] compareEventEnabled;
        private readonly IFlagRegisterField[] compareReached;

        private readonly LimitTimer tickTimer;
        private readonly LimitTimer overflowTimer; // OVRFLW
        private readonly ComparingTimer[] innerTimers;

        private readonly int numberOfEvents;
        private const ulong InitialFrequency = 32768;
        private const int MaxNumberOfEvents = 4;
        // OVRFLW: the period the stock model's ComparingTimer actually wraps
        // its 24-bit counter at (`limit: 0xFFFFFF`). The overflow timer MUST
        // share it or the event drifts out of phase with COUNTER.
        private const ulong CounterPeriod = 0xFFFFFF;

        private enum Register : long
        {
            Start = 0x000,
            Stop = 0x004,
            Clear = 0x008,
            TriggerOverflow = 0x00C,
            Tick = 0x100,
            Overflow = 0x104,
            Compare0EventPending = 0x140,
            Compare1EventPending = 0x144,
            Compare2EventPending = 0x148,
            Compare3EventPending = 0x14C,
            InterruptEnableSet = 0x304,
            InterruptEnableClear = 0x308,
            EventEnable = 0x340,
            EventSet = 0x344,
            EventClear = 0x348,
            Counter = 0x504,
            Prescaler = 0x508,
            Compare0 = 0x540,
            Compare1 = 0x544,
            Compare2 = 0x548,
            Compare3 = 0x54C
        }
    }
}
