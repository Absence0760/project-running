// Renode model of the Sharp Memory LCD (LS013B4DN04 family, 168x144 mono).
//
// Runtime-compiled by the `include @SharpMipDisplay.cs` line in watch.resc.
// Decodes the same wire protocol the sharp_mip driver crate encodes (see
// drivers/sharp_mip/src/display.rs): frames are delimited by the active-HIGH
// chip-select GPIO (input 0 of this peripheral), byte 0 carries the M0/M1/M2
// mode bits, then [line addr (1-based)][21 data bytes][trailer] repeats per
// line. Data bytes arrive LSB-first on real glass; Renode's SPI models hand
// over logical byte values, so bit 0 is the leftmost pixel of its group and
// 1 = white, matching the driver's composition exactly.
//
// showAnalyzer gives a live window; DumpFrame writes a binary PPM (P6) for
// headless verification (bin/watch-sim.sh --screenshot).

using System;
using System.IO;
using Antmicro.Renode.Backends.Display;
using Antmicro.Renode.Core;
using Antmicro.Renode.Logging;
using Antmicro.Renode.Peripherals.SPI;
using Antmicro.Renode.Peripherals.Video;

namespace Antmicro.Renode.Peripherals.Video
{
    public class SharpMipDisplay : AutoRepaintingVideo, ISPIPeripheral, IGPIOReceiver
    {
        public SharpMipDisplay(IMachine machine) : base(machine)
        {
            Reconfigure(PanelWidth, PanelHeight, PixelFormat.RGB888);
            pixelsWhite = new bool[PanelHeight, PanelWidth];
            frameBytes = new byte[MaxFrameBytes];
            Reset();
        }

        public override void Reset()
        {
            lock(pixelsWhite)
            {
                for(var y = 0; y < PanelHeight; y++)
                {
                    for(var x = 0; x < PanelWidth; x++)
                    {
                        pixelsWhite[y, x] = true;
                    }
                }
            }
            frameLength = 0;
            csAsserted = false;
        }

        // Input 0: the panel's SCS line (active HIGH). A falling edge closes
        // the frame and triggers the decode.
        public void OnGPIO(int number, bool value)
        {
            if(number != 0)
            {
                return;
            }
            if(value)
            {
                frameLength = 0;
                csAsserted = true;
                return;
            }
            if(!csAsserted)
            {
                return;
            }
            csAsserted = false;
            DecodeFrame();
        }

        public byte Transmit(byte data)
        {
            if(csAsserted && frameLength < frameBytes.Length)
            {
                frameBytes[frameLength++] = data;
            }
            return 0x00; // MOSI-only device; MISO is not connected
        }

        public void FinishTransmission()
        {
            // Frames are CS-delimited, and one frame spans many EasyDMA
            // transfers — nothing to do per transfer.
        }

        public void DumpFrame(string path)
        {
            lock(pixelsWhite)
            {
                using(var stream = new FileStream(path, FileMode.Create, FileAccess.Write))
                using(var writer = new StreamWriter(stream))
                {
                    writer.Write($"P6\n{PanelWidth} {PanelHeight}\n255\n");
                    writer.Flush();
                    for(var y = 0; y < PanelHeight; y++)
                    {
                        for(var x = 0; x < PanelWidth; x++)
                        {
                            var rgb = pixelsWhite[y, x] ? White : Black;
                            stream.WriteByte(rgb[0]);
                            stream.WriteByte(rgb[1]);
                            stream.WriteByte(rgb[2]);
                        }
                    }
                }
            }
            this.Log(LogLevel.Info, "Dumped frame to {0}", path);
        }

        protected override void Repaint()
        {
            lock(pixelsWhite)
            {
                var i = 0;
                for(var y = 0; y < PanelHeight; y++)
                {
                    for(var x = 0; x < PanelWidth; x++)
                    {
                        var rgb = pixelsWhite[y, x] ? White : Black;
                        buffer[i++] = rgb[0];
                        buffer[i++] = rgb[1];
                        buffer[i++] = rgb[2];
                    }
                }
            }
        }

        private void DecodeFrame()
        {
            if(frameLength == 0)
            {
                return;
            }
            var mode = frameBytes[0];
            if((mode & ModeClear) != 0)
            {
                this.Log(LogLevel.Debug, "Clear-all frame");
                lock(pixelsWhite)
                {
                    for(var y = 0; y < PanelHeight; y++)
                    {
                        for(var x = 0; x < PanelWidth; x++)
                        {
                            pixelsWhite[y, x] = true;
                        }
                    }
                }
                return;
            }
            if((mode & ModeWrite) == 0)
            {
                return; // VCOM-maintenance frame
            }
            var lines = 0;
            lock(pixelsWhite)
            {
                var i = 1;
                while(i + LineBytes + 1 < frameLength)
                {
                    var address = frameBytes[i];
                    if(address == 0 || address > PanelHeight)
                    {
                        break;
                    }
                    var y = address - 1;
                    for(var x = 0; x < PanelWidth; x++)
                    {
                        var b = frameBytes[i + 1 + x / 8];
                        pixelsWhite[y, x] = ((b >> (x % 8)) & 1) == 1;
                    }
                    i += 1 + LineBytes + 1; // addr + data + trailer
                    lines++;
                }
            }
            this.Log(LogLevel.Noisy, "Wrote {0} line(s)", lines);
        }

        private const int PanelWidth = 168;
        private const int PanelHeight = 144;
        private const int LineBytes = PanelWidth / 8;
        private const byte ModeWrite = 0x01;
        private const byte ModeClear = 0x04;
        // mode + 144 * (addr + data + trailer) + final trailer, with slack
        private const int MaxFrameBytes = 2 + PanelHeight * (LineBytes + 2) + 64;

        private static readonly byte[] White = { 0xEC, 0xEF, 0xE8 };
        private static readonly byte[] Black = { 0x12, 0x14, 0x12 };

        private readonly bool[,] pixelsWhite;
        private readonly byte[] frameBytes;
        private int frameLength;
        private bool csAsserted;
    }
}
