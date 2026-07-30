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
// The rendered canvas is wider than the panel: bezel strips flanking the
// LCD draw five clickable BTN1..BTN5 buttons at the decisions.md §81
// Garmin-Fenix positions their §350 functions occupy — BTN1 (start/pause)
// upper-right, BTN4 (page right) lower-right, BTN2 (stop) mid-left in the
// UP slot, BTN3 (page left) lower-left in the DOWN slot, BTN5 (lap)
// upper-left in the LIGHT slot. The class implements
// IAbsolutePositionPointerInput, which Renode's video analyzer auto-attaches
// (VideoAnalyzer.FindPointers picks any IPointerInput in the machine), so a
// mouse press/release on a bezel button in the --gui window drives the same
// gpio0 pin the watch.resc btn macros pull — the pin stays low as long as
// the mouse button is held. Clicks need `buttonPort` (gpio0) passed at
// construction; without it the bezel is drawn but inert.
//
// showAnalyzer gives a live window. Two PPM (P6) dumps serve the headless
// side, and they are different artifacts: DumpFrame writes the LCD area only
// (no case), flat black/white, and is what every assertion reads — its bytes
// are a contract. DumpCanvas writes the whole window including the case and
// keys, in the canvas palette, and asserts nothing; it exists so the shell's
// own look can be reviewed without a display attached.

using System;
using System.Collections.Generic;
using System.IO;
using Antmicro.Renode.Backends.Display;
using Antmicro.Renode.Core;
using Antmicro.Renode.Logging;
using Antmicro.Renode.Peripherals.Input;
using Antmicro.Renode.Peripherals.SPI;
using Antmicro.Renode.Peripherals.Video;

namespace Antmicro.Renode.Peripherals.Video
{
    public class SharpMipDisplay : AutoRepaintingVideo, ISPIPeripheral, IGPIOReceiver, IAbsolutePositionPointerInput
    {
        public SharpMipDisplay(IMachine machine, IGPIOReceiver buttonPort = null) : base(machine)
        {
            this.buttonPort = buttonPort;
            Reconfigure(CanvasWidth, CanvasHeight, PixelFormat.RGB888);
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
            ReleasePressedButton();
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

        // The whole analyzer canvas — case, keys and panel — as the --gui window
        // draws it. DumpFrame is the LCD's own pixels and stays the artifact any
        // assertion reads; this is the device shell, which has no truth to assert
        // and exists so the window's own look can be reviewed (and regressed)
        // without a display attached.
        public void DumpCanvas(string path)
        {
            lock(pixelsWhite)
            {
                using(var stream = new FileStream(path, FileMode.Create, FileAccess.Write))
                using(var writer = new StreamWriter(stream))
                {
                    writer.Write($"P6\n{CanvasWidth} {CanvasHeight}\n255\n");
                    writer.Flush();
                    stream.Write(buffer, 0, CanvasWidth * CanvasHeight * 3);
                }
            }
            this.Log(LogLevel.Info, "Dumped canvas to {0}", path);
        }

        // --- IAbsolutePositionPointerInput: the analyzer window scales click
        // coordinates over the drawn image into 0..MaxX/0..MaxY, so with the
        // canvas dimensions here a coordinate is (almost) a canvas pixel.

        public int MaxX { get { return CanvasWidth - 1; } }
        public int MaxY { get { return CanvasHeight - 1; } }
        public int MinX { get { return 0; } }
        public int MinY { get { return 0; } }

        public void MoveTo(int x, int y)
        {
            pointerX = x;
            pointerY = y;
        }

        public void Press(MouseButton button = MouseButton.Left)
        {
            if(button != MouseButton.Left || buttonPort == null)
            {
                return;
            }
            var idx = HitButton(pointerX, pointerY);
            if(idx < 0)
            {
                return;
            }
            pressedIndex = idx;
            buttonPort.OnGPIO(ButtonPins[idx], false); // active-low press
            this.Log(LogLevel.Debug, "BTN{0} pressed in the analyzer window", idx + 1);
        }

        public void Release(MouseButton button = MouseButton.Left)
        {
            if(button != MouseButton.Left)
            {
                return;
            }
            ReleasePressedButton();
        }

        protected override void Repaint()
        {
            lock(pixelsWhite)
            {
                for(var y = 0; y < PanelHeight; y++)
                {
                    var i = (y * CanvasWidth + PanelLeft) * 3;
                    for(var x = 0; x < PanelWidth; x++)
                    {
                        // PanelPaper/PanelInk, not the White/Black DumpFrame
                        // writes: a Sharp Memory LCD is a reflective panel, so
                        // its "white" is a silvery green and its "black" a warm
                        // dark grey, never #fff on #000. The dump keeps the flat
                        // pair so its bytes — and every assertion over them —
                        // stay exactly what they were.
                        var rgb = pixelsWhite[y, x] ? PanelPaper : PanelInk;
                        buffer[i++] = rgb[0];
                        buffer[i++] = rgb[1];
                        buffer[i++] = rgb[2];
                    }
                }
            }
            DrawBezel();
        }

        private void ReleasePressedButton()
        {
            var idx = pressedIndex;
            if(idx < 0 || buttonPort == null)
            {
                return;
            }
            pressedIndex = -1;
            buttonPort.OnGPIO(ButtonPins[idx], true); // back to idle high
        }

        private static int HitButton(int x, int y)
        {
            for(var i = 0; i < ButtonPins.Length; i++)
            {
                if(x >= ButtonX[i] && x < ButtonX[i] + ButtonWidth
                    && y >= ButtonY[i] && y < ButtonY[i] + ButtonHeight)
                {
                    return i;
                }
            }
            return -1;
        }

        // The case, the five keys, and a rim around the glass. Geometry is
        // deliberately unchanged from the flat first version — CanvasWidth,
        // ButtonX and ButtonY all still hold, so the click mapping and
        // HitButton boxes are the same pixels they always were and this is
        // purely how those pixels are coloured.
        private void DrawBezel()
        {
            FillRect(0, 0, BezelWidth, CanvasHeight, CaseBody);
            FillRect(PanelLeft + PanelWidth, 0, BezelWidth, CanvasHeight, CaseBody);
            // A lit top edge and a shadowed bottom one: one pixel each, and the
            // only thing separating a flat grey strip from something that reads
            // as a moulded case.
            for(var x = 0; x < CanvasWidth; x++)
            {
                if(x < BezelWidth || x >= PanelLeft + PanelWidth)
                {
                    SetPixel(x, 0, CaseLit);
                    SetPixel(x, CanvasHeight - 1, CaseShadow);
                }
            }
            // The glass sits in a recess, so its edge carries a rim: shadowed on
            // the side the light comes from, lit on the far one.
            for(var y = 0; y < PanelHeight; y++)
            {
                SetPixel(PanelLeft - 1, y, CaseShadow);
                SetPixel(PanelLeft + PanelWidth, y, CaseLit);
            }
            RoundCorners();

            var pressed = pressedIndex;
            for(var i = 0; i < ButtonPins.Length; i++)
            {
                var down = i == pressed;
                var fill = down ? KeyDown : KeyFill;
                var ink = down ? KeyDownText : KeyText;
                FillRect(ButtonX[i], ButtonY[i], ButtonWidth, ButtonHeight, fill);
                DrawRectOutline(ButtonX[i], ButtonY[i], ButtonWidth, ButtonHeight, down ? KeyEdgeDown : KeyEdge);
                // Two lines: which key, and what § 350 makes it do. The number
                // alone made the window a wiring diagram — you had to already
                // know the grammar to drive it.
                CenteredText(i, ButtonY[i] + 2, "B" + (i + 1), ink);
                CenteredText(i, ButtonY[i] + ButtonHeight - GlyphHeight - 2, ButtonLabels[i], ink);
            }
        }

        private void CenteredText(int index, int y, string text, byte[] rgb)
        {
            var textWidth = text.Length * (GlyphWidth + 1) - 1;
            DrawText(ButtonX[index] + (ButtonWidth - textWidth) / 2, y, text, rgb);
        }

        // Knock the four canvas corners back to the window background so the
        // case reads as a rounded body rather than a rectangle.
        private void RoundCorners()
        {
            for(var y = 0; y < CornerRadius; y++)
            {
                for(var x = 0; x < CornerRadius; x++)
                {
                    var dx = CornerRadius - 1 - x;
                    var dy = CornerRadius - 1 - y;
                    if(dx * dx + dy * dy <= CornerRadius * CornerRadius)
                    {
                        continue;
                    }
                    SetPixel(x, y, Outside);
                    SetPixel(CanvasWidth - 1 - x, y, Outside);
                    SetPixel(x, CanvasHeight - 1 - y, Outside);
                    SetPixel(CanvasWidth - 1 - x, CanvasHeight - 1 - y, Outside);
                }
            }
        }

        private void FillRect(int x0, int y0, int w, int h, byte[] rgb)
        {
            for(var y = y0; y < y0 + h; y++)
            {
                for(var x = x0; x < x0 + w; x++)
                {
                    SetPixel(x, y, rgb);
                }
            }
        }

        private void DrawRectOutline(int x0, int y0, int w, int h, byte[] rgb)
        {
            for(var x = x0; x < x0 + w; x++)
            {
                SetPixel(x, y0, rgb);
                SetPixel(x, y0 + h - 1, rgb);
            }
            for(var y = y0; y < y0 + h; y++)
            {
                SetPixel(x0, y, rgb);
                SetPixel(x0 + w - 1, y, rgb);
            }
        }

        private void DrawText(int x0, int y0, string text, byte[] rgb)
        {
            var x = x0;
            foreach(var c in text)
            {
                byte[] glyph;
                if(Font.TryGetValue(c, out glyph))
                {
                    for(var row = 0; row < GlyphHeight; row++)
                    {
                        for(var col = 0; col < GlyphWidth; col++)
                        {
                            if(((glyph[row] >> (GlyphWidth - 1 - col)) & 1) == 1)
                            {
                                SetPixel(x + col, y0 + row, rgb);
                            }
                        }
                    }
                }
                x += GlyphWidth + 1;
            }
        }

        private void SetPixel(int x, int y, byte[] rgb)
        {
            var i = (y * CanvasWidth + x) * 3;
            buffer[i] = rgb[0];
            buffer[i + 1] = rgb[1];
            buffer[i + 2] = rgb[2];
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

        // Bezel geometry: a strip either side of the LCD, one box per button
        // at the §81 Fenix slot its function maps to (see the file header).
        private const int BezelWidth = 31;
        private const int PanelLeft = BezelWidth;
        private const int CanvasWidth = BezelWidth + PanelWidth + BezelWidth;
        private const int CanvasHeight = PanelHeight;
        private const int ButtonHeight = 18;
        private const int ButtonWidth = 27;
        private const int ButtonInset = 2;
        private const int GlyphWidth = 5;
        private const int GlyphHeight = 7;

        // BTN1..BTN5 -> P0.11, P0.12, P0.24, P0.25, P0.02 — the same pins the
        // watch.resc btn macros drive (and the BSP assigns); keep all three in
        // lockstep. ButtonX/Y are indexed to match: BTN1 upper-right
        // (start/pause), BTN2 mid-left (stop), BTN3 lower-left (page left),
        // BTN4 lower-right (page right), BTN5 upper-left (lap).
        private static readonly int[] ButtonPins = { 11, 12, 24, 25, 2 };
        private const int LeftColX = ButtonInset;
        private const int RightColX = CanvasWidth - ButtonWidth - ButtonInset;
        private static readonly int[] ButtonX = { RightColX, LeftColX, LeftColX, RightColX, LeftColX };
        private static readonly int[] ButtonY = { 14, 63, 112, 112, 14 };

        // DumpFrame's pair. Flat by design and NOT the canvas colours: every
        // assertion over a dump reads these bytes, so they do not move.
        private static readonly byte[] White = { 0xEC, 0xEF, 0xE8 };
        private static readonly byte[] Black = { 0x12, 0x14, 0x12 };

        // The canvas palette. A reflective Sharp MIP has no backlight — the
        // paper is a silvery green and the ink a warm dark grey, which is what
        // the panel reads as in daylight.
        private static readonly byte[] PanelPaper = { 0xC7, 0xD1, 0xC2 };
        private static readonly byte[] PanelInk = { 0x1E, 0x22, 0x1B };
        private static readonly byte[] CaseBody = { 0x24, 0x26, 0x29 };
        private static readonly byte[] CaseLit = { 0x3C, 0x3F, 0x44 };
        private static readonly byte[] CaseShadow = { 0x12, 0x13, 0x15 };
        private static readonly byte[] Outside = { 0x0A, 0x0B, 0x0C };
        private static readonly byte[] KeyFill = { 0x33, 0x36, 0x3B };
        private static readonly byte[] KeyEdge = { 0x60, 0x65, 0x6C };
        private static readonly byte[] KeyText = { 0xD6, 0xDA, 0xE0 };
        private static readonly byte[] KeyDown = { 0xC7, 0xD1, 0xC2 };
        private static readonly byte[] KeyEdgeDown = { 0xE8, 0xF0, 0xE4 };
        private static readonly byte[] KeyDownText = { 0x14, 0x18, 0x12 };

        private const int CornerRadius = 7;

        // What § 350 makes each key do, indexed like ButtonPins/ButtonX/ButtonY.
        private static readonly string[] ButtonLabels = { "STRT", "STOP", "PREV", "NEXT", "LAP" };

        // 5x7 glyphs, bit 4 = leftmost column; only the bezel labels' chars.
        private static readonly Dictionary<char, byte[]> Font = new Dictionary<char, byte[]>
        {
            { 'B', new byte[] { 0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E } },
            { 'T', new byte[] { 0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04 } },
            { 'N', new byte[] { 0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11 } },
            { '1', new byte[] { 0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E } },
            { '2', new byte[] { 0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F } },
            { '3', new byte[] { 0x1E, 0x01, 0x01, 0x0E, 0x01, 0x01, 0x1E } },
            { '4', new byte[] { 0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02 } },
            { '5', new byte[] { 0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E } },
            { 'S', new byte[] { 0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E } },
            { 'R', new byte[] { 0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11 } },
            { 'O', new byte[] { 0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E } },
            { 'P', new byte[] { 0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10 } },
            { 'E', new byte[] { 0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F } },
            { 'V', new byte[] { 0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04 } },
            { 'X', new byte[] { 0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11 } },
            { 'L', new byte[] { 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F } },
            { 'A', new byte[] { 0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11 } },
        };

        private readonly IGPIOReceiver buttonPort;
        private readonly bool[,] pixelsWhite;
        private readonly byte[] frameBytes;
        private int frameLength;
        private bool csAsserted;
        private volatile int pointerX;
        private volatile int pointerY;
        private volatile int pressedIndex = -1;
    }
}
