//
// NRF52840_TWIM — an nRF52840 TWIM (I2C master with EasyDMA) model.
//
// Why this exists: the stock Renode platform declares twi0/twi1 as
// I2C.NRF52840_I2C, which models the *legacy* nRF51-style TWI byte interface
// (single-byte TXD/RXD data registers, ENABLE=5). The firmware's embassy-nrf
// `twim` driver programs the TWIM EasyDMA interface instead — ENABLE=6,
// TXD.PTR/MAXCNT + RXD.PTR/MAXCNT buffer descriptors, and the LASTTX/LASTRX
// shortcut matrix — none of which the stock model maps. Every transaction
// therefore hung with no STOPPED event, and the sensor tasks' async
// timeout-probes concluded the part was absent ("no BMP581 on I2C (probe
// timed out); task parked"). This model implements the TWIM register subset
// the driver uses, completing each transfer synchronously inside the task
// write (the same instantaneous-transfer simplification as the easyDMA path
// of Renode's NRF52840_SPI):
//
//   - TASKS_STARTTX reads TXD.MAXCNT bytes at TXD.PTR from guest RAM and
//     hands them to the addressed II2CPeripheral's Write();
//   - TASKS_STARTRX asks the device's Read() for RXD.MAXCNT bytes and lands
//     them at RXD.PTR (padding with 0xFF if the device under-returns);
//   - the LASTTX_STARTRX / LASTTX_SUSPEND / LASTTX_STOP / LASTRX_STARTTX /
//     LASTRX_SUSPEND / LASTRX_STOP shortcuts chain the phases the way the
//     hardware event system would, so a write_read is one repeated-start
//     transaction; TASKS_STOP (or a *_STOP shortcut) fires EVENTS_STOPPED
//     and FinishTransmission() — the I2C STOP condition;
//   - an ADDRESS with no registered child raises ERRORSRC.ANACK +
//     EVENTS_ERROR, which embassy surfaces as Error::AddressNack — an absent
//     sensor still parks its task, now via the honest NACK path;
//   - INTENSET/INTENCLR + the event registers drive the IRQ as a level, so
//     both the driver's blocking spin-wait and its interrupt-driven async
//     wait complete (INTENSET written while an event is already pending
//     still asserts).
//
// Register offsets and bit positions follow the nRF52840 PS v1.x TWIM
// chapter, cross-checked against nrf-pac 0.3.0 (what embassy-nrf 0.10
// compiles against). sim/watch.resc re-registers this model over the stock
// twi1; sensors attach as ordinary I2C children (`bmp581: ... @ twi1 0x46`).
//
using System;
using System.Linq;

using Antmicro.Renode.Core;
using Antmicro.Renode.Core.Structure;
using Antmicro.Renode.Core.Structure.Registers;
using Antmicro.Renode.Logging;
using Antmicro.Renode.Peripherals.Bus;

namespace Antmicro.Renode.Peripherals.I2C
{
    public class NRF52840_TWIM : SimpleContainer<II2CPeripheral>, IDoubleWordPeripheral, IProvidesRegisterCollection<DoubleWordRegisterCollection>, IKnownSize
    {
        public NRF52840_TWIM(IMachine machine) : base(machine)
        {
            sysbus = machine.GetSystemBus(this);
            IRQ = new GPIO();
            RegistersCollection = new DoubleWordRegisterCollection(this);
            DefineRegisters();
            Reset();
        }

        public override void Reset()
        {
            enabled = false;
            currentSlave = null;
            errorAnack = false;
            errorDnack = false;
            errorOverrun = false;
            RegistersCollection.Reset();
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

        public DoubleWordRegisterCollection RegistersCollection { get; }

        public long Size => 0x1000;

        private void DefineRegisters()
        {
            Registers.TasksStartRx.Define(this)
                .WithFlag(0, FieldMode.Write, name: "TASKS_STARTRX", writeCallback: (_, val) =>
                {
                    if(!val)
                    {
                        return;
                    }
                    if(TryResolveSlave())
                    {
                        DoRx();
                    }
                    UpdateInterrupts();
                })
                .WithReservedBits(1, 31);

            Registers.TasksStartTx.Define(this)
                .WithFlag(0, FieldMode.Write, name: "TASKS_STARTTX", writeCallback: (_, val) =>
                {
                    if(!val)
                    {
                        return;
                    }
                    if(TryResolveSlave())
                    {
                        DoTx();
                    }
                    UpdateInterrupts();
                })
                .WithReservedBits(1, 31);

            Registers.TasksStop.Define(this)
                .WithFlag(0, FieldMode.Write, name: "TASKS_STOP", writeCallback: (_, val) =>
                {
                    if(!val)
                    {
                        return;
                    }
                    DoStop();
                    UpdateInterrupts();
                })
                .WithReservedBits(1, 31);

            Registers.TasksSuspend.Define(this)
                .WithFlag(0, FieldMode.Write, name: "TASKS_SUSPEND", writeCallback: (_, val) =>
                {
                    if(!val)
                    {
                        return;
                    }
                    suspendedPending.Value = true;
                    UpdateInterrupts();
                })
                .WithReservedBits(1, 31);

            Registers.TasksResume.Define(this)
                // Transfers complete synchronously at the task write, so there
                // is never a suspended transfer for RESUME to continue.
                .WithFlag(0, FieldMode.Write, name: "TASKS_RESUME")
                .WithReservedBits(1, 31);

            Registers.EventsStopped.Define(this)
                .WithFlag(0, out stoppedPending, name: "EVENTS_STOPPED")
                .WithReservedBits(1, 31)
                .WithWriteCallback((_, __) => UpdateInterrupts());

            Registers.EventsError.Define(this)
                .WithFlag(0, out errorPending, name: "EVENTS_ERROR")
                .WithReservedBits(1, 31)
                .WithWriteCallback((_, __) => UpdateInterrupts());

            Registers.EventsSuspended.Define(this)
                .WithFlag(0, out suspendedPending, name: "EVENTS_SUSPENDED")
                .WithReservedBits(1, 31)
                .WithWriteCallback((_, __) => UpdateInterrupts());

            Registers.EventsRxStarted.Define(this)
                .WithFlag(0, out rxStartedPending, name: "EVENTS_RXSTARTED")
                .WithReservedBits(1, 31)
                .WithWriteCallback((_, __) => UpdateInterrupts());

            Registers.EventsTxStarted.Define(this)
                .WithFlag(0, out txStartedPending, name: "EVENTS_TXSTARTED")
                .WithReservedBits(1, 31)
                .WithWriteCallback((_, __) => UpdateInterrupts());

            Registers.EventsLastRx.Define(this)
                .WithFlag(0, out lastRxPending, name: "EVENTS_LASTRX")
                .WithReservedBits(1, 31)
                .WithWriteCallback((_, __) => UpdateInterrupts());

            Registers.EventsLastTx.Define(this)
                .WithFlag(0, out lastTxPending, name: "EVENTS_LASTTX")
                .WithReservedBits(1, 31)
                .WithWriteCallback((_, __) => UpdateInterrupts());

            Registers.Shorts.Define(this)
                .WithFlag(7, out shortLastTxStartRx, name: "LASTTX_STARTRX")
                .WithFlag(8, out shortLastTxSuspend, name: "LASTTX_SUSPEND")
                .WithFlag(9, out shortLastTxStop, name: "LASTTX_STOP")
                .WithFlag(10, out shortLastRxStartTx, name: "LASTRX_STARTTX")
                .WithFlag(11, out shortLastRxSuspend, name: "LASTRX_SUSPEND")
                .WithFlag(12, out shortLastRxStop, name: "LASTRX_STOP");

            Registers.Inten.Define(this)
                .WithFlag(1, FieldMode.Read, name: "STOPPED", valueProviderCallback: _ => intStopped.Value)
                .WithFlag(9, FieldMode.Read, name: "ERROR", valueProviderCallback: _ => intError.Value)
                .WithFlag(18, FieldMode.Read, name: "SUSPENDED", valueProviderCallback: _ => intSuspended.Value)
                .WithFlag(19, FieldMode.Read, name: "RXSTARTED", valueProviderCallback: _ => intRxStarted.Value)
                .WithFlag(20, FieldMode.Read, name: "TXSTARTED", valueProviderCallback: _ => intTxStarted.Value)
                .WithFlag(23, FieldMode.Read, name: "LASTRX", valueProviderCallback: _ => intLastRx.Value)
                .WithFlag(24, FieldMode.Read, name: "LASTTX", valueProviderCallback: _ => intLastTx.Value)
                .WithIgnoredBits(0, 1)
                .WithIgnoredBits(2, 7)
                .WithIgnoredBits(10, 8)
                .WithIgnoredBits(21, 2)
                .WithIgnoredBits(25, 7);

            Registers.IntenSet.Define(this)
                .WithFlag(1, out intStopped, FieldMode.Set | FieldMode.Read, name: "STOPPED")
                .WithFlag(9, out intError, FieldMode.Set | FieldMode.Read, name: "ERROR")
                .WithFlag(18, out intSuspended, FieldMode.Set | FieldMode.Read, name: "SUSPENDED")
                .WithFlag(19, out intRxStarted, FieldMode.Set | FieldMode.Read, name: "RXSTARTED")
                .WithFlag(20, out intTxStarted, FieldMode.Set | FieldMode.Read, name: "TXSTARTED")
                .WithFlag(23, out intLastRx, FieldMode.Set | FieldMode.Read, name: "LASTRX")
                .WithFlag(24, out intLastTx, FieldMode.Set | FieldMode.Read, name: "LASTTX")
                .WithIgnoredBits(0, 1)
                .WithIgnoredBits(2, 7)
                .WithIgnoredBits(10, 8)
                .WithIgnoredBits(21, 2)
                .WithIgnoredBits(25, 7)
                .WithChangeCallback((_, __) => UpdateInterrupts());

            Registers.IntenClr.Define(this)
                .WithFlag(1, name: "STOPPED",
                    writeCallback: (_, val) => intStopped.Value &= !val,
                    valueProviderCallback: _ => intStopped.Value)
                .WithFlag(9, name: "ERROR",
                    writeCallback: (_, val) => intError.Value &= !val,
                    valueProviderCallback: _ => intError.Value)
                .WithFlag(18, name: "SUSPENDED",
                    writeCallback: (_, val) => intSuspended.Value &= !val,
                    valueProviderCallback: _ => intSuspended.Value)
                .WithFlag(19, name: "RXSTARTED",
                    writeCallback: (_, val) => intRxStarted.Value &= !val,
                    valueProviderCallback: _ => intRxStarted.Value)
                .WithFlag(20, name: "TXSTARTED",
                    writeCallback: (_, val) => intTxStarted.Value &= !val,
                    valueProviderCallback: _ => intTxStarted.Value)
                .WithFlag(23, name: "LASTRX",
                    writeCallback: (_, val) => intLastRx.Value &= !val,
                    valueProviderCallback: _ => intLastRx.Value)
                .WithFlag(24, name: "LASTTX",
                    writeCallback: (_, val) => intLastTx.Value &= !val,
                    valueProviderCallback: _ => intLastTx.Value)
                .WithIgnoredBits(0, 1)
                .WithIgnoredBits(2, 7)
                .WithIgnoredBits(10, 8)
                .WithIgnoredBits(21, 2)
                .WithIgnoredBits(25, 7)
                .WithChangeCallback((_, __) => UpdateInterrupts());

            Registers.ErrorSrc.Define(this)
                // Write-1-to-clear, per the PS (embassy's clear_errorsrc
                // writes all ones before every transaction).
                .WithFlag(0, name: "OVERRUN",
                    writeCallback: (_, val) => errorOverrun &= !val,
                    valueProviderCallback: _ => errorOverrun)
                .WithFlag(1, name: "ANACK",
                    writeCallback: (_, val) => errorAnack &= !val,
                    valueProviderCallback: _ => errorAnack)
                .WithFlag(2, name: "DNACK",
                    writeCallback: (_, val) => errorDnack &= !val,
                    valueProviderCallback: _ => errorDnack);

            Registers.Enable.Define(this)
                .WithValueField(0, 4, name: "ENABLE", writeCallback: (_, val) =>
                {
                    enabled = val == EnableTwim;
                    if(val != 0 && !enabled)
                    {
                        // 5 would be the legacy TWI mode this model deliberately
                        // does not implement (the stock NRF52840_I2C covers it).
                        this.Log(LogLevel.Warning, "ENABLE written with unsupported value 0x{0:X} — only TWIM (6) is modelled", val);
                    }
                }, valueProviderCallback: _ => enabled ? EnableTwim : 0u);

            // Pin selects and bus frequency: accepted and readable, no
            // behavioural effect on an instantaneous-transfer model.
            Registers.PselScl.Define(this, 0xFFFFFFFF)
                .WithValueField(0, 32, name: "PSEL_SCL");
            Registers.PselSda.Define(this, 0xFFFFFFFF)
                .WithValueField(0, 32, name: "PSEL_SDA");
            Registers.Frequency.Define(this, 0x04000000)
                .WithValueField(0, 32, name: "FREQUENCY");

            Registers.RxdPtr.Define(this)
                .WithValueField(0, 32, out rxPtr, name: "RXD_PTR");
            Registers.RxdMaxCnt.Define(this)
                .WithValueField(0, 16, out rxMaxCnt, name: "RXD_MAXCNT")
                .WithReservedBits(16, 16);
            Registers.RxdAmount.Define(this)
                .WithValueField(0, 16, out rxAmount, FieldMode.Read, name: "RXD_AMOUNT")
                .WithReservedBits(16, 16);
            Registers.RxdList.Define(this)
                .WithValueField(0, 3, name: "RXD_LIST")
                .WithReservedBits(3, 29);

            Registers.TxdPtr.Define(this)
                .WithValueField(0, 32, out txPtr, name: "TXD_PTR");
            Registers.TxdMaxCnt.Define(this)
                .WithValueField(0, 16, out txMaxCnt, name: "TXD_MAXCNT")
                .WithReservedBits(16, 16);
            Registers.TxdAmount.Define(this)
                .WithValueField(0, 16, out txAmount, FieldMode.Read, name: "TXD_AMOUNT")
                .WithReservedBits(16, 16);
            Registers.TxdList.Define(this)
                .WithValueField(0, 3, name: "TXD_LIST")
                .WithReservedBits(3, 29);

            Registers.Address.Define(this)
                .WithValueField(0, 7, out address, name: "ADDRESS")
                .WithReservedBits(7, 25);
        }

        // Resolve the child device at ADDRESS, or raise the address-NACK the
        // driver maps to Error::AddressNack. Resolution happens per task (not
        // at the ADDRESS write) so late-registered devices are found and the
        // NACK is raised on the transaction that actually addressed them.
        private bool TryResolveSlave()
        {
            if(!enabled)
            {
                this.Log(LogLevel.Warning, "Transfer started while the peripheral is disabled — ignoring");
                return false;
            }
            if(!TryGetByAddress((int)address.Value, out currentSlave))
            {
                this.Log(LogLevel.Warning, "No device at address 0x{0:X} — raising ANACK", address.Value);
                errorAnack = true;
                errorPending.Value = true;
                return false;
            }
            return true;
        }

        private void DoTx()
        {
            txStartedPending.Value = true;
            var count = (int)txMaxCnt.Value;
            if(count == 0)
            {
                // With nothing to send LASTTX never fires (no last byte); the
                // driver triggers STOP/SUSPEND manually in this case.
                return;
            }
            var data = sysbus.ReadBytes(txPtr.Value, count);
            this.Log(LogLevel.Noisy, "TX {0} byte(s) to 0x{1:X}", count, address.Value);
            currentSlave.Write(data);
            txAmount.Value = (ulong)count;
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
            }
        }

        private void DoRx()
        {
            rxStartedPending.Value = true;
            var count = (int)rxMaxCnt.Value;
            if(count == 0)
            {
                // Zero-length read: LASTRX never fires; the driver STOPs manually.
                return;
            }
            var data = currentSlave.Read(count);
            if(data.Length != count)
            {
                var adjusted = Enumerable.Repeat((byte)0xFF, count).ToArray();
                Array.Copy(data, adjusted, Math.Min(data.Length, count));
                data = adjusted;
            }
            sysbus.WriteBytes(data, rxPtr.Value);
            this.Log(LogLevel.Noisy, "RX {0} byte(s) from 0x{1:X}", count, address.Value);
            rxAmount.Value = (ulong)count;
            lastRxPending.Value = true;
            if(shortLastRxStop.Value)
            {
                DoStop();
            }
            else if(shortLastRxStartTx.Value)
            {
                DoTx();
            }
            else if(shortLastRxSuspend.Value)
            {
                suspendedPending.Value = true;
            }
        }

        private void DoStop()
        {
            currentSlave?.FinishTransmission();
            currentSlave = null;
            stoppedPending.Value = true;
        }

        private void UpdateInterrupts()
        {
            var pending =
                (stoppedPending.Value && intStopped.Value) ||
                (errorPending.Value && intError.Value) ||
                (suspendedPending.Value && intSuspended.Value) ||
                (rxStartedPending.Value && intRxStarted.Value) ||
                (txStartedPending.Value && intTxStarted.Value) ||
                (lastRxPending.Value && intLastRx.Value) ||
                (lastTxPending.Value && intLastTx.Value);
            IRQ.Set(pending);
        }

        private IFlagRegisterField stoppedPending;
        private IFlagRegisterField errorPending;
        private IFlagRegisterField suspendedPending;
        private IFlagRegisterField rxStartedPending;
        private IFlagRegisterField txStartedPending;
        private IFlagRegisterField lastRxPending;
        private IFlagRegisterField lastTxPending;

        private IFlagRegisterField intStopped;
        private IFlagRegisterField intError;
        private IFlagRegisterField intSuspended;
        private IFlagRegisterField intRxStarted;
        private IFlagRegisterField intTxStarted;
        private IFlagRegisterField intLastRx;
        private IFlagRegisterField intLastTx;

        private IFlagRegisterField shortLastTxStartRx;
        private IFlagRegisterField shortLastTxSuspend;
        private IFlagRegisterField shortLastTxStop;
        private IFlagRegisterField shortLastRxStartTx;
        private IFlagRegisterField shortLastRxSuspend;
        private IFlagRegisterField shortLastRxStop;

        private IValueRegisterField rxPtr;
        private IValueRegisterField rxMaxCnt;
        private IValueRegisterField rxAmount;
        private IValueRegisterField txPtr;
        private IValueRegisterField txMaxCnt;
        private IValueRegisterField txAmount;
        private IValueRegisterField address;

        private bool enabled;
        private bool errorAnack;
        private bool errorDnack;
        private bool errorOverrun;
        private II2CPeripheral currentSlave;

        private readonly IBusController sysbus;

        private const uint EnableTwim = 6;

        private enum Registers : long
        {
            TasksStartRx = 0x000,
            TasksStartTx = 0x008,
            TasksStop = 0x014,
            TasksSuspend = 0x01C,
            TasksResume = 0x020,
            EventsStopped = 0x104,
            EventsError = 0x124,
            EventsSuspended = 0x148,
            EventsRxStarted = 0x14C,
            EventsTxStarted = 0x150,
            EventsLastRx = 0x15C,
            EventsLastTx = 0x160,
            Shorts = 0x200,
            Inten = 0x300,
            IntenSet = 0x304,
            IntenClr = 0x308,
            ErrorSrc = 0x4C4,
            Enable = 0x500,
            PselScl = 0x508,
            PselSda = 0x50C,
            Frequency = 0x524,
            RxdPtr = 0x534,
            RxdMaxCnt = 0x538,
            RxdAmount = 0x53C,
            RxdList = 0x540,
            TxdPtr = 0x544,
            TxdMaxCnt = 0x548,
            TxdAmount = 0x54C,
            TxdList = 0x550,
            Address = 0x588,
        }
    }
}
