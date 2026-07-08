# Drains the defmt-rtt up-buffer from emulated RAM into a host file.
#
# Renode's bundled scripts/single-node/segger-rtt.py hooks the SEGGER C
# library's function symbols (SEGGER_RTT_WriteNoLock etc.), which don't exist
# in this firmware: the defmt-rtt Rust crate implements the RTT control block
# directly and only exports the `_SEGGER_RTT` data symbol. So instead of
# function hooks, this polls the control block on a virtual-time managed
# thread, copies out any new bytes, and advances the read offset so the
# firmware never sees a full buffer. The output file carries raw defmt frames;
# decode on the host with `defmt-print -e <elf>` (bin/watch-sim.sh does).
#
# Runs under Renode's embedded IronPython 2: keep this file ASCII-only (no
# encoding declaration is honoured) and Python-2 compatible (no f-strings).
#
# Control-block layout (defmt-rtt, 32-bit target):
#   _SEGGER_RTT: id[16] | max_up: u32 | max_down: u32 | up_channel
#   up_channel:  name: u32 | buffer: u32 | size: u32 | write: u32 | read: u32 | flags: u32

CHANNEL_OFFSET = 24
RTT_ID = "SEGGER RTT"


def mc_setup_defmt_rtt(output_path, poll_hz=50):
    machine = monitor.Machine
    bus = machine.SystemBus
    cpu = bus.GetCPUs()[0]

    found, addresses = bus.TryGetAllSymbolAddresses("_SEGGER_RTT", context=cpu)
    if not found:
        cpu.ErrorLog("_SEGGER_RTT symbol not found - load the ELF before calling setup_defmt_rtt")
        return
    base = list(addresses)[0]
    chan = base + CHANNEL_OFFSET

    out = open(output_path, "wb", 0)

    def poll():
        # cortex-m-rt copies .data (including the control-block ID) into RAM
        # at reset - don't touch the channel until the ID shows up.
        ident = "".join(chr(b) for b in bus.ReadBytes(base, len(RTT_ID)))
        if ident != RTT_ID:
            return
        buf = bus.ReadDoubleWord(chan + 4)
        size = bus.ReadDoubleWord(chan + 8)
        wr = bus.ReadDoubleWord(chan + 12)
        rd = bus.ReadDoubleWord(chan + 16)
        if buf == 0 or size == 0 or wr == rd or wr >= size or rd >= size:
            return
        if wr > rd:
            data = bytearray(bus.ReadBytes(buf + rd, int(wr - rd)))
        else:
            data = bytearray(bus.ReadBytes(buf + rd, int(size - rd)))
            data += bytearray(bus.ReadBytes(buf, int(wr)))
        out.write(bytes(data))
        # IronPython doesn't honour buffering=0 (writes sit in the .NET
        # FileStream buffer and are lost when Renode is SIGTERMed), so flush
        # per drain - the consumer tails this file live anyway.
        out.flush()
        bus.WriteDoubleWord(chan + 16, wr)

    thread = machine.ObtainManagedThread(poll, int(poll_hz))
    thread.Start()
    cpu.InfoLog("defmt-rtt drain active: _SEGGER_RTT at 0x%X, polling at %d Hz" % (int(base), int(poll_hz)))
