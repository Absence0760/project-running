//
// NRF52840_TWIM — an EasyDMA (TWIM) I2C master model for the nRF52840.
//
// Why this exists: the stock Renode platform declares twi0/twi1 as
// I2C.NRF52840_I2C, which models only the *legacy* TWI register interface
// (single-byte TXD/RXD at 0x51C/0x518, ENABLE=5). The firmware's embassy-nrf
// `Twim` driver programs the *TWIM* interface instead — ENABLE=6, EasyDMA
// buffers via TXD.PTR/MAXCNT + RXD.PTR/MAXCNT, the LASTTX/LASTRX SHORTS
// chain, and completion signalled by EVENTS_STOPPED / EVENTS_ERROR. On the
// stock model every one of those registers is unmapped, ENABLE=6 logs "Wrong
// enabled value", no event ever fires, and the hr task's presence probe times
// out — which is why the MAX86177 path was bench-gated. On real hardware TWI
// and TWIM share the 0x40003000 slot and the chip honours whichever interface
// ENABLE selects; sim/watch.resc re-registers this model there (same pattern
// as NRF52840_RTC_Overflow).
//
// Modelled subset — exactly what embassy-nrf 0.10 twim.rs drives:
//   - TASKS_STARTTX / TASKS_STARTRX with TXD/RXD PTR + MAXCNT and the
//     written-back AMOUNT registers (`check_tx`/`check_rx` compare them);
//   - SHORTS: LASTTX_STARTRX, LASTTX_SUSPEND, LASTTX_STOP, LASTRX_STARTTX,
//     LASTRX_STOP (the write→read chain of `read_regs` runs entirely in
//     hardware-short order);
//   - EVENTS_STOPPED / EVENTS_ERROR / EVENTS_SUSPENDED (+ LASTTX/LASTRX/
//     TXSTARTED/RXSTARTED for completeness) with INTENSET/INTENCLR and a
//     level IRQ — the async probe path completes via the interrupt, the
//     blocking driver path spins on the event registers;
//   - ERRORSRC with write-1-to-clear ANACK/DNACK/OVERRUN; a transfer to an
//     address with no attached peripheral raises ANACK + EVENTS_ERROR, so an
//     absent sensor fails fast as AddressNack instead of hanging;
//   - ENABLE (6 = TWIM; 0 = disabled; anything else is logged and treated as
//     disabled), PSEL/FREQUENCY/LIST as plain stores.
//
// Deliberate simplifications (all fine for this firmware, noted for honesty):
//   - transfers complete in zero virtual time inside the task-register write
//     (no per-byte bus timing) — same simplification the SPI display path
//     already lives with;
//   - TASKS_SUSPEND/TASKS_RESUME are modelled only as far as the driver uses
//     them (events; a suspended transfer never parks half-done because
//     transfers are instantaneous);
//   - a zero-length STARTTX/STARTRX still runs its SHORTS as if LASTTX/LASTRX
//     fired (real hardware wouldn't fire them; embassy never programs a
//     zero-length DMA leg — it issues STOP directly instead).
//
using System;
using System.Collections.Generic;

using Antmicro.Renode.Core;
using Antmicro.Renode.Core.Structure;
using Antmicro.Renode.Core.Structure.Registers;
using Antmicro.Renode.Logging;
using Antmicro.Renode.Peripherals.Bus;

namespace Antmicro.Renode.Peripherals.I2C
{
    public class NRF52840_TWIM : SimpleContainer<II2CPeripheral>, IProvidesRegisterCollection<DoubleWordRegisterCollection>, IDoubleWordPeripheral, IKnownSize
    {
        public NRF52840_TWIM(IMachine machine) : base(machine)
        {
            IRQ = new GPIO();
            sysbus = machine.GetSystemBus(this);
            RegistersCollection = new DoubleWordRegisterCollection(this);
            DefineRegisters();
        }

        public override void Reset()
        {
            RegistersCollection.Reset();
            enabled = false;
            UpdateInterrupts();
        }

        public uint ReadDoubleWord(long offset)
        {
            return RegistersCollection.Read(offset);
        }

        public void WriteDoubleWord(long offset, uint value)
        {
            RegistersCollection.Write(offset, value);
        }

        public GPIO IRQ { get; }

        public long Size => 0x1000;

        public DoubleWordRegisterCollection RegistersCollection { get; }

        private void DefineRegisters()
        {
            Registers.StartRx.Define(this)
                .WithFlag(0, FieldMode.Write, name: "TASKS_STARTRX", writeCallback: (_, val) =>
                {
                    if(val)
                    {
                        DoRx();
                    }
                })
                .WithReservedBits(1, 31)
            ;

            Registers.StartTx.Define(this)
                .WithFlag(0, FieldMode.Write, name: "TASKS_STARTTX", writeCallback: (_, val) =>
                {
                    if(val)
                    {
                        DoTx();
                    }
                })
                .WithReservedBits(1, 31)
            ;

            Registers.Stop.Define(this)
                .WithFlag(0, FieldMode.Write, name: "TASKS_STOP", writeCallback: (_, val) =>
                {
                    if(val)
                    {
                        DoStop();
                    }
                })
                .WithReservedBits(1, 31)
            ;

            Registers.Suspend.Define(this)
                .WithFlag(0, FieldMode.Write, name: "TASKS_SUSPEND", writeCallback: (_, val) =>
                {
                    if(val)
                    {
                        suspendedPending.Value = true;
                        UpdateInterrupts();
                    }
                })
                .WithReservedBits(1, 31)
            ;

            Registers.Resume.Define(this)
                // Transfers complete instantaneously, so there is never a
                // suspended transfer to resume — accept silently.
                .WithFlag(0, FieldMode.Write, name: "TASKS_RESUME")
                .WithReservedBits(1, 31)
            ;

            Registers.EventsStopped.Define(this)
                .WithFlag(0, out stoppedPending, name: "EVENTS_STOPPED")
                .WithReservedBits(1, 31)
                .WithWriteCallback((_, __) => UpdateInterrupts())
            ;

            Registers.EventsError.Define(this)
                .WithFlag(0, out errorPending, name: "EVENTS_ERROR")
                .WithReservedBits(1, 31)
                .WithWriteCallback((_, __) => UpdateInterrupts())
            ;

            Registers.EventsSuspended.Define(this)
                .WithFlag(0, out suspendedPending, name: "EVENTS_SUSPENDED")
                .WithReservedBits(1, 31)
                .WithWriteCallback((_, __) => UpdateInterrupts())
            ;

            Registers.EventsRxStarted.Define(this)
                .WithFlag(0, out rxStartedPending, name: "EVENTS_RXSTARTED")
                .WithReservedBits(1, 31)
                .WithWriteCallback((_, __) => UpdateInterrupts())
            ;

            Registers.EventsTxStarted.Define(this)
                .WithFlag(0, out txStartedPending, name: "EVENTS_TXSTARTED")
                .WithReservedBits(1, 31)
                .WithWriteCallback((_, __) => UpdateInterrupts())
            ;

            Registers.EventsLastRx.Define(this)
                .WithFlag(0, out lastRxPending, name: "EVENTS_LASTRX")
                .WithReservedBits(1, 31)
                .WithWriteCallback((_, __) => UpdateInterrupts())
            ;

            Registers.EventsLastTx.Define(this)
                .WithFlag(0, out lastTxPending, name: "EVENTS_LASTTX")
                .WithReservedBits(1, 31)
                .WithWriteCallback((_, __) => UpdateInterrupts())
            ;

            Registers.Shorts.Define(this)
                .WithReservedBits(0, 7)
                .WithFlag(7, out shortLastTxStartRx, name: "LASTTX_STARTRX")
                .WithFlag(8, out shortLastTxSuspend, name: "LASTTX_SUSPEND")
                .WithFlag(9, out shortLastTxStop, name: "LASTTX_STOP")
                .WithFlag(10, out shortLastRxStartTx, name: "LASTRX_STARTTX")
                .WithReservedBits(11, 1)
                .WithFlag(12, out shortLastRxStop, name: "LASTRX_STOP")
                .WithReservedBits(13, 19)
            ;

            Registers.IntenSet.Define(this)
                .WithIgnoredBits(0, 1)
                .WithFlag(1, out stoppedInterruptEnabled, FieldMode.Read | FieldMode.Set, name: "STOPPED")
                .WithIgnoredBits(2, 7)
                .WithFlag(9, out errorInterruptEnabled, FieldMode.Read | FieldMode.Set, name: "ERROR")
                .WithIgnoredBits(10, 8)
                .WithFlag(18, out suspendedInterruptEnabled, FieldMode.Read | FieldMode.Set, name: "SUSPENDED")
                .WithFlag(19, out rxStartedInterruptEnabled, FieldMode.Read | FieldMode.Set, name: "RXSTARTED")
                .WithFlag(20, out txStartedInterruptEnabled, FieldMode.Read | FieldMode.Set, name: "TXSTARTED")
                .WithIgnoredBits(21, 2)
                .WithFlag(23, out lastRxInterruptEnabled, FieldMode.Read | FieldMode.Set, name: "LASTRX")
                .WithFlag(24, out lastTxInterruptEnabled, FieldMode.Read | FieldMode.Set, name: "LASTTX")
                .WithIgnoredBits(25, 7)
                .WithWriteCallback((_, __) => UpdateInterrupts())
            ;

            Registers.IntenClr.Define(this)
                .WithIgnoredBits(0, 1)
                .WithFlag(1, name: "STOPPED",
                    writeCallback: (_, val) => stoppedInterruptEnabled.Value &= !val,
                    valueProviderCallback: _ => stoppedInterruptEnabled.Value)
                .WithIgnoredBits(2, 7)
                .WithFlag(9, name: "ERROR",
                    writeCallback: (_, val) => errorInterruptEnabled.Value &= !val,
                    valueProviderCallback: _ => errorInterruptEnabled.Value)
                .WithIgnoredBits(10, 8)
                .WithFlag(18, name: "SUSPENDED",
                    writeCallback: (_, val) => suspendedInterruptEnabled.Value &= !val,
                    valueProviderCallback: _ => suspendedInterruptEnabled.Value)
                .WithFlag(19, name: "RXSTARTED",
                    writeCallback: (_, val) => rxStartedInterruptEnabled.Value &= !val,
                    valueProviderCallback: _ => rxStartedInterruptEnabled.Value)
                .WithFlag(20, name: "TXSTARTED",
                    writeCallback: (_, val) => txStartedInterruptEnabled.Value &= !val,
                    valueProviderCallback: _ => txStartedInterruptEnabled.Value)
                .WithIgnoredBits(21, 2)
                .WithFlag(23, name: "LASTRX",
                    writeCallback: (_, val) => lastRxInterruptEnabled.Value &= !val,
                    valueProviderCallback: _ => lastRxInterruptEnabled.Value)
                .WithFlag(24, name: "LASTTX",
                    writeCallback: (_, val) => lastTxInterruptEnabled.Value &= !val,
                    valueProviderCallback: _ => lastTxInterruptEnabled.Value)
                .WithIgnoredBits(25, 7)
                .WithWriteCallback((_, __) => UpdateInterrupts())
            ;

            Registers.ErrorSrc.Define(this)
                .WithFlag(0, out overrunError, FieldMode.Read | FieldMode.WriteOneToClear, name: "OVERRUN")
                .WithFlag(1, out addressNackError, FieldMode.Read | FieldMode.WriteOneToClear, name: "ANACK")
                .WithFlag(2, out dataNackError, FieldMode.Read | FieldMode.WriteOneToClear, name: "DNACK")
                .WithReservedBits(3, 29)
            ;

            Registers.Enable.Define(this)
                .WithValueField(0, 4, name: "ENABLE", writeCallback: (_, val) =>
                {
                    switch(val)
                    {
                    case 0:
                        enabled = false;
                        break;
                    case 6:
                        enabled = true;
                        break;
                    default:
                        // 5 would be legacy TWI — this model is TWIM-only.
                        this.Log(LogLevel.Warning, "Unsupported ENABLE value {0}; treating as disabled", val);
                        enabled = false;
                        break;
                    }
                })
                .WithReservedBits(4, 28)
            ;

            Registers.PselScl.Define(this)
                .WithValueField(0, 32, name: "PSEL_SCL")
            ;

            Registers.PselSda.Define(this)
                .WithValueField(0, 32, name: "PSEL_SDA")
            ;

            Registers.Frequency.Define(this)
                .WithValueField(0, 32, name: "FREQUENCY")
            ;

            Registers.RxdPtr.Define(this)
                .WithValueField(0, 32, out rxPtr, name: "RXD_PTR")
            ;

            Registers.RxdMaxcnt.Define(this)
                .WithValueField(0, 16, out rxMaxcnt, name: "RXD_MAXCNT")
                .WithReservedBits(16, 16)
            ;

            Registers.RxdAmount.Define(this)
                .WithValueField(0, 16, out rxAmount, FieldMode.Read, name: "RXD_AMOUNT")
                .WithReservedBits(16, 16)
            ;

            Registers.RxdList.Define(this)
                .WithValueField(0, 3, name: "RXD_LIST")
                .WithReservedBits(3, 29)
            ;

            Registers.TxdPtr.Define(this)
                .WithValueField(0, 32, out txPtr, name: "TXD_PTR")
            ;

            Registers.TxdMaxcnt.Define(this)
                .WithValueField(0, 16, out txMaxcnt, name: "TXD_MAXCNT")
                .WithReservedBits(16, 16)
            ;

            Registers.TxdAmount.Define(this)
                .WithValueField(0, 16, out txAmount, FieldMode.Read, name: "TXD_AMOUNT")
                .WithReservedBits(16, 16)
            ;

            Registers.TxdList.Define(this)
                .WithValueField(0, 3, name: "TXD_LIST")
                .WithReservedBits(3, 29)
            ;

            Registers.Address.Define(this)
                .WithValueField(0, 7, out address, name: "ADDRESS")
                .WithReservedBits(7, 25)
            ;
        }

        private void DoTx()
        {
            if(!TryGetSlave(out var slave))
            {
                return;
            }

            var count = (int)txMaxcnt.Value;
            var data = count > 0 ? sysbus.ReadBytes(txPtr.Value, count) : new byte[0];
            this.Log(LogLevel.Noisy, "TX {0} byte(s) to 0x{1:X}", count, address.Value);
            slave.Write(data);
            txAmount.Value = (uint)count;
            txStartedPending.Value = true;
            lastTxPending.Value = true;

            if(shortLastTxStartRx.Value)
            {
                DoRx();
            }
            else if(shortLastTxStop.Value)
            {
                DoStop();
            }
            else if(shortLastTxSuspend.Value)
            {
                suspendedPending.Value = true;
                UpdateInterrupts();
            }
            else
            {
                UpdateInterrupts();
            }
        }

        private void DoRx()
        {
            if(!TryGetSlave(out var slave))
            {
                return;
            }

            var count = (int)rxMaxcnt.Value;
            var data = count > 0 ? slave.Read(count) : new byte[0];
            var buffer = new byte[count];
            for(var i = 0; i < count; i++)
            {
                // Pad with the bus-idle pattern if the peripheral returned
                // fewer bytes than the master clocked out.
                buffer[i] = i < data.Length ? data[i] : (byte)0xFF;
            }
            if(count > 0)
            {
                sysbus.WriteBytes(buffer, rxPtr.Value);
            }
            this.Log(LogLevel.Noisy, "RX {0} byte(s) from 0x{1:X}", count, address.Value);
            rxAmount.Value = (uint)count;
            rxStartedPending.Value = true;
            lastRxPending.Value = true;

            if(shortLastRxStartTx.Value)
            {
                DoTx();
            }
            else if(shortLastRxStop.Value)
            {
                DoStop();
            }
            else
            {
                UpdateInterrupts();
            }
        }

        private void DoStop()
        {
            if(TryGetByAddress((int)address.Value, out var slave))
            {
                slave.FinishTransmission();
            }
            stoppedPending.Value = true;
            UpdateInterrupts();
        }

        private bool TryGetSlave(out II2CPeripheral slave)
        {
            slave = null;
            if(!enabled)
            {
                this.Log(LogLevel.Warning, "Transfer attempted on a disabled controller");
                return false;
            }
            if(!TryGetByAddress((int)address.Value, out slave))
            {
                // No device on the bus at this address: address NACK, exactly
                // what a probe of an unpopulated bus should see.
                this.Log(LogLevel.Noisy, "No peripheral at address 0x{0:X} — ANACK", address.Value);
                addressNackError.Value = true;
                errorPending.Value = true;
                UpdateInterrupts();
                return false;
            }
            return true;
        }

        private void UpdateInterrupts()
        {
            var flag = false;
            flag |= stoppedPending.Value && stoppedInterruptEnabled.Value;
            flag |= errorPending.Value && errorInterruptEnabled.Value;
            flag |= suspendedPending.Value && suspendedInterruptEnabled.Value;
            flag |= rxStartedPending.Value && rxStartedInterruptEnabled.Value;
            flag |= txStartedPending.Value && txStartedInterruptEnabled.Value;
            flag |= lastRxPending.Value && lastRxInterruptEnabled.Value;
            flag |= lastTxPending.Value && lastTxInterruptEnabled.Value;
            IRQ.Set(flag);
        }

        private bool enabled;

        private IFlagRegisterField stoppedPending;
        private IFlagRegisterField errorPending;
        private IFlagRegisterField suspendedPending;
        private IFlagRegisterField rxStartedPending;
        private IFlagRegisterField txStartedPending;
        private IFlagRegisterField lastRxPending;
        private IFlagRegisterField lastTxPending;

        private IFlagRegisterField shortLastTxStartRx;
        private IFlagRegisterField shortLastTxSuspend;
        private IFlagRegisterField shortLastTxStop;
        private IFlagRegisterField shortLastRxStartTx;
        private IFlagRegisterField shortLastRxStop;

        private IFlagRegisterField stoppedInterruptEnabled;
        private IFlagRegisterField errorInterruptEnabled;
        private IFlagRegisterField suspendedInterruptEnabled;
        private IFlagRegisterField rxStartedInterruptEnabled;
        private IFlagRegisterField txStartedInterruptEnabled;
        private IFlagRegisterField lastRxInterruptEnabled;
        private IFlagRegisterField lastTxInterruptEnabled;

        private IFlagRegisterField overrunError;
        private IFlagRegisterField addressNackError;
        private IFlagRegisterField dataNackError;

        private IValueRegisterField rxPtr;
        private IValueRegisterField rxMaxcnt;
        private IValueRegisterField rxAmount;
        private IValueRegisterField txPtr;
        private IValueRegisterField txMaxcnt;
        private IValueRegisterField txAmount;
        private IValueRegisterField address;

        private readonly IBusController sysbus;

        private enum Registers : long
        {
            StartRx = 0x000,
            StartTx = 0x008,
            Stop = 0x014,
            Suspend = 0x01C,
            Resume = 0x020,
            EventsStopped = 0x104,
            EventsError = 0x124,
            EventsSuspended = 0x148,
            EventsRxStarted = 0x14C,
            EventsTxStarted = 0x150,
            EventsLastRx = 0x15C,
            EventsLastTx = 0x160,
            Shorts = 0x200,
            IntenSet = 0x304,
            IntenClr = 0x308,
            ErrorSrc = 0x4C4,
            Enable = 0x500,
            PselScl = 0x508,
            PselSda = 0x50C,
            Frequency = 0x524,
            RxdPtr = 0x534,
            RxdMaxcnt = 0x538,
            RxdAmount = 0x53C,
            RxdList = 0x540,
            TxdPtr = 0x544,
            TxdMaxcnt = 0x548,
            TxdAmount = 0x54C,
            TxdList = 0x550,
            Address = 0x588
        }
    }
}
