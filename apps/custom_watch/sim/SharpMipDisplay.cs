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
// The rendered canvas is a device, not a strip: the panel draws at 3x into
// a recessed glass opening inside a shaded, rounded watch case, and the five
// BTN1..BTN5 keys are clickable capsules protruding from the case sides at
// the decisions.md §81 Garmin-Fenix positions their §350 functions occupy —
// BTN1 (start/pause) upper-right, BTN4 (page right) lower-right, BTN2 (stop)
// mid-left in the UP slot, BTN3 (page left) lower-left in the DOWN slot,
// BTN5 (lap) upper-left in the LIGHT slot, each with its function etched on
// the case shoulder beside it. The shell (case, ring, glass, labels, resting
// keys) is composed once into a cached backdrop; a repaint block-copies it,
// blits the panel, and repaints at most one pressed key. The class implements
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

        // Monitor-callable hit test (0-based key index, -1 outside every key)
        // so an external viewer (sim/live_view.py) can map canvas clicks to
        // keys without duplicating the geometry — it then fires the virtual-
        // time btn macros, which press more reliably than raw pin drives.
        public int HitButtonAt(int x, int y)
        {
            return HitButton(x, y);
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
            if(shellCache == null)
            {
                BuildShellCache();
            }
            Array.Copy(shellCache, buffer, shellCache.Length);
            lock(pixelsWhite)
            {
                for(var y = 0; y < PanelHeight; y++)
                {
                    for(var x = 0; x < PanelWidth; x++)
                    {
                        // PanelPaper/PanelInk, not the White/Black DumpFrame
                        // writes: a Sharp Memory LCD is a reflective panel, so
                        // its "white" is a silvery green and its "black" a warm
                        // dark grey, never #fff on #000. The dump keeps the flat
                        // pair so its bytes — and every assertion over them —
                        // stay exactly what they were.
                        var rgb = pixelsWhite[y, x] ? PanelPaper : PanelInk;
                        var left = PanelLeft + x * Scale;
                        for(var dy = 0; dy < Scale; dy++)
                        {
                            var i = ((PanelTop + y * Scale + dy) * CanvasWidth + left) * 3;
                            for(var dx = 0; dx < Scale; dx++)
                            {
                                // The last row/column of each Scale-wide cell
                                // is nudged dark: the inter-pixel gap a real
                                // MIP shows, and what keeps the 3x blow-up
                                // reading as glass rather than a flat fill.
                                var gap = dy == Scale - 1 || dx == Scale - 1;
                                buffer[i++] = gap ? (byte)(rgb[0] - (rgb[0] >> 4)) : rgb[0];
                                buffer[i++] = gap ? (byte)(rgb[1] - (rgb[1] >> 4)) : rgb[1];
                                buffer[i++] = gap ? (byte)(rgb[2] - (rgb[2] >> 4)) : rgb[2];
                            }
                        }
                    }
                }
            }
            var pressed = pressedIndex;
            if(pressed >= 0)
            {
                DrawKey(pressed, true);
            }
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

        // The shell: shaded case, bezel ring, glass recess, and the five keys
        // at rest, composed once into a cached backdrop. Every hit box reads
        // the same ButtonX/ButtonY/ButtonWidth/ButtonHeight the key painter
        // does, so the click map cannot drift from the pixels.
        private void BuildShellCache()
        {
            shellCache = new byte[CanvasWidth * CanvasHeight * 3];
            Fill(shellCache, Outside);

            FillRoundedRect(shellCache, CaseX, CaseY, CaseW, CaseH, CaseRadius, CaseTop, CaseBottom);
            EdgeLine(shellCache, CaseX + CaseRadius, CaseX + CaseW - CaseRadius, CaseY + 1, CaseLit);

            var ringX = PanelLeft - GlassMargin - BezelRing;
            var ringY = PanelTop - GlassMargin - BezelRing;
            var ringW = PanelWidth * Scale + 2 * (GlassMargin + BezelRing);
            var ringH = PanelHeight * Scale + 2 * (GlassMargin + BezelRing);
            FillRoundedRect(shellCache, ringX, ringY, ringW, ringH, RingRadius, RingTop, RingBottom);
            EdgeLine(shellCache, ringX + RingRadius, ringX + ringW - RingRadius, ringY + 1, RingLit);

            FillRoundedRect(shellCache, PanelLeft - GlassMargin, PanelTop - GlassMargin,
                PanelWidth * Scale + 2 * GlassMargin, PanelHeight * Scale + 2 * GlassMargin,
                GlassRadius, Glass, Glass);

            // The inactive glass: real Sharp MIP panels carry a border of the
            // same reflective material around the active area, with no pixel
            // structure — which is why text on real glass never reads as
            // touching the bezel. Drawn flat (no inter-pixel texture), so the
            // active area's pixel grid still reads as exactly the panel.
            FillRoundedRect(shellCache, PanelLeft - InactiveGlass, PanelTop - InactiveGlass,
                PanelWidth * Scale + 2 * InactiveGlass, PanelHeight * Scale + 2 * InactiveGlass,
                2, PanelPaper, PanelPaper);

            for(var i = 0; i < ButtonPins.Length; i++)
            {
                DrawKeyInto(shellCache, i, false);
            }
        }

        private void DrawKey(int index, bool down)
        {
            DrawKeyInto(buffer, index, down);
        }

        // A key is a rounded tab riding the case edge, carrying its § 350
        // function word with its BTN number beneath — the function prominent,
        // because the number alone made the window a wiring diagram.
        private void DrawKeyInto(byte[] dst, int index, bool down)
        {
            var x = ButtonX[index];
            var y = ButtonY[index];
            if(down)
            {
                // Pressed keys light in the panel's own paper green — the
                // loudest confirmation the palette has.
                FillRoundedRect(dst, x, y, ButtonWidth, ButtonHeight, KeyRadius, KeyDown, KeyDown);
            }
            else
            {
                FillRoundedRect(dst, x, y, ButtonWidth, ButtonHeight, KeyRadius, KeyTop, KeyBottom);
                EdgeLine(dst, x + KeyRadius, x + ButtonWidth - KeyRadius, y + 1, KeyLit);
            }
            var ink = down ? KeyDownText : KeyText;
            var tag = down ? KeyDownText : KeyTagText;
            var word = ButtonLabels[index];
            DrawText(dst, x + (ButtonWidth - TextWidth(word, 2)) / 2, y + 9, word, 2, ink);
            var num = "B" + (index + 1);
            DrawText(dst, x + (ButtonWidth - TextWidth(num, 1)) / 2, y + ButtonHeight - GlyphHeight - 8, num, 1, tag);
        }

        private static void Fill(byte[] dst, byte[] rgb)
        {
            for(var i = 0; i < dst.Length; i += 3)
            {
                dst[i] = rgb[0];
                dst[i + 1] = rgb[1];
                dst[i + 2] = rgb[2];
            }
        }

        // Rounded rectangle with a vertical top->bottom gradient, edges
        // anti-aliased by signed-distance coverage against whatever the
        // destination already holds.
        private void FillRoundedRect(byte[] dst, int x0, int y0, int w, int h, int r, byte[] top, byte[] bottom)
        {
            var hw = w / 2.0;
            var hh = h / 2.0;
            var cx = x0 + hw;
            var cy = y0 + hh;
            for(var y = y0; y < y0 + h; y++)
            {
                if(y < 0 || y >= CanvasHeight)
                {
                    continue;
                }
                var t = (y - y0) / (double)(h - 1);
                var rr = (byte)(top[0] + (bottom[0] - top[0]) * t);
                var gg = (byte)(top[1] + (bottom[1] - top[1]) * t);
                var bb = (byte)(top[2] + (bottom[2] - top[2]) * t);
                for(var x = x0; x < x0 + w; x++)
                {
                    if(x < 0 || x >= CanvasWidth)
                    {
                        continue;
                    }
                    var dx = Math.Max(Math.Abs(x + 0.5 - cx) - (hw - r), 0.0);
                    var dy = Math.Max(Math.Abs(y + 0.5 - cy) - (hh - r), 0.0);
                    var dist = Math.Sqrt(dx * dx + dy * dy) - r;
                    var cover = Math.Min(Math.Max(0.5 - dist, 0.0), 1.0);
                    if(cover <= 0.0)
                    {
                        continue;
                    }
                    var i = (y * CanvasWidth + x) * 3;
                    dst[i] = (byte)(dst[i] + (rr - dst[i]) * cover);
                    dst[i + 1] = (byte)(dst[i + 1] + (gg - dst[i + 1]) * cover);
                    dst[i + 2] = (byte)(dst[i + 2] + (bb - dst[i + 2]) * cover);
                }
            }
        }

        // One-pixel specular line along a shape's flat top span — the light
        // that separates a moulded surface from a flat fill.
        private void EdgeLine(byte[] dst, int xFrom, int xTo, int y, byte[] rgb)
        {
            for(var x = xFrom; x < xTo; x++)
            {
                SetPixel(dst, x, y, rgb);
            }
        }

        private static int TextWidth(string text, int scale)
        {
            return text.Length * (GlyphWidth + 1) * scale - scale;
        }

        private void DrawText(byte[] dst, int x0, int y0, string text, int scale, byte[] rgb)
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
                            if(((glyph[row] >> (GlyphWidth - 1 - col)) & 1) != 1)
                            {
                                continue;
                            }
                            for(var dy = 0; dy < scale; dy++)
                            {
                                for(var dx = 0; dx < scale; dx++)
                                {
                                    SetPixel(dst, x + col * scale + dx, y0 + row * scale + dy, rgb);
                                }
                            }
                        }
                    }
                }
                x += (GlyphWidth + 1) * scale;
            }
        }

        private void SetPixel(byte[] dst, int x, int y, byte[] rgb)
        {
            if(x < 0 || x >= CanvasWidth || y < 0 || y >= CanvasHeight)
            {
                return;
            }
            var i = (y * CanvasWidth + x) * 3;
            dst[i] = rgb[0];
            dst[i + 1] = rgb[1];
            dst[i + 2] = rgb[2];
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

        // Shell geometry. The panel draws at Scale into a glass recess inside
        // a bezel ring inside the case; the keys are tabs riding the case's
        // side edges at the §81 Fenix slots (see the file header). Everything
        // derives from these so the layout stays one set of knobs.
        private const int Scale = 3;
        private const int GlassMargin = 14;
        private const int InactiveGlass = 9;
        private const int BezelRing = 12;
        private const int CaseSide = 62;
        private const int CaseTopBand = 26;
        private const int CaseX = 22;
        private const int CaseY = 6;
        private const int CaseRadius = 52;
        private const int RingRadius = 18;
        private const int GlassRadius = 8;
        private const int PanelLeft = CaseX + CaseSide + BezelRing + GlassMargin;
        private const int PanelTop = CaseY + CaseTopBand + BezelRing + GlassMargin;
        private const int CanvasWidth = 2 * PanelLeft + PanelWidth * Scale;
        private const int CanvasHeight = 2 * PanelTop + PanelHeight * Scale;
        private const int CaseW = CanvasWidth - 2 * CaseX;
        private const int CaseH = CanvasHeight - 2 * CaseY;
        private const int ButtonWidth = 66;
        private const int ButtonHeight = 48;
        private const int KeyRadius = 14;
        private const int GlyphWidth = 5;
        private const int GlyphHeight = 7;

        // BTN1..BTN5 -> P0.11, P0.12, P0.24, P0.25, P0.02 — the same pins the
        // watch.resc btn macros drive (and the BSP assigns); keep all three in
        // lockstep. ButtonX/Y are indexed to match: BTN1 upper-right
        // (start/pause), BTN2 mid-left (stop), BTN3 lower-left (page left),
        // BTN4 lower-right (page right), BTN5 upper-left (lap).
        private static readonly int[] ButtonPins = { 11, 12, 24, 25, 2 };
        private const int LeftColX = 8;
        private const int RightColX = CanvasWidth - ButtonWidth - 8;
        private static readonly int[] ButtonX = { RightColX, LeftColX, LeftColX, RightColX, LeftColX };
        private static readonly int[] ButtonY = {
            (int)(CanvasHeight * 0.28) - ButtonHeight / 2,
            CanvasHeight / 2 - ButtonHeight / 2,
            (int)(CanvasHeight * 0.80) - ButtonHeight / 2,
            (int)(CanvasHeight * 0.72) - ButtonHeight / 2,
            (int)(CanvasHeight * 0.20) - ButtonHeight / 2,
        };

        // DumpFrame's pair. Flat by design and NOT the canvas colours: every
        // assertion over a dump reads these bytes, so they do not move.
        private static readonly byte[] White = { 0xEC, 0xEF, 0xE8 };
        private static readonly byte[] Black = { 0x12, 0x14, 0x12 };

        // The canvas palette. A reflective Sharp MIP has no backlight — the
        // paper is a silvery green and the ink a warm dark grey, which is what
        // the panel reads as in daylight. The case and keys are a cool dark
        // titanium, shaded top-to-bottom under an implied high light.
        private static readonly byte[] PanelPaper = { 0xC7, 0xD1, 0xC2 };
        private static readonly byte[] PanelInk = { 0x1E, 0x22, 0x1B };
        private static readonly byte[] Outside = { 0x0A, 0x0B, 0x0C };
        private static readonly byte[] CaseTop = { 0x43, 0x47, 0x4F };
        private static readonly byte[] CaseBottom = { 0x20, 0x23, 0x28 };
        private static readonly byte[] CaseLit = { 0x6E, 0x74, 0x7E };
        private static readonly byte[] RingTop = { 0x2E, 0x32, 0x39 };
        private static readonly byte[] RingBottom = { 0x14, 0x16, 0x1A };
        private static readonly byte[] RingLit = { 0x77, 0x7E, 0x8A };
        private static readonly byte[] Glass = { 0x0B, 0x0D, 0x0F };
        private static readonly byte[] KeyTop = { 0x3A, 0x3F, 0x47 };
        private static readonly byte[] KeyBottom = { 0x1B, 0x1E, 0x23 };
        private static readonly byte[] KeyLit = { 0x6E, 0x75, 0x81 };
        private static readonly byte[] KeyText = { 0xD6, 0xDA, 0xE0 };
        private static readonly byte[] KeyTagText = { 0x8A, 0x92, 0x9E };
        private static readonly byte[] KeyDown = { 0xC7, 0xD1, 0xC2 };
        private static readonly byte[] KeyDownText = { 0x14, 0x18, 0x12 };

        // What § 350 makes each key do, indexed like ButtonPins/ButtonX/ButtonY.
        private static readonly string[] ButtonLabels = { "START", "STOP", "PREV", "NEXT", "LAP" };

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
        private byte[] shellCache;
        private int frameLength;
        private bool csAsserted;
        private volatile int pointerX;
        private volatile int pointerY;
        private volatile int pressedIndex = -1;
    }
}
