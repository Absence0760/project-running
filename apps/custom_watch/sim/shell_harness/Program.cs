// Feed a preview PPM into the SharpMipDisplay model over its own wire format,
// repaint, and dump three artifacts: canvas.ppm (the --gui window at rest),
// canvas-pressed.ppm (BTN2 held through the analyzer's pointer path), and
// frame.ppm (the assertion contract — diff it against the pre-change bytes;
// a shell edit must leave it byte-identical).
//
// This is the host loop for editing the sim's watch shell on a machine with
// no Renode: dotnet build is the compile check (against Stubs.cs — see the
// csproj note on its limits), the PPMs are the visual check.

using System;
using System.IO;
using Antmicro.Renode.Peripherals.Video;

public static class Program
{
    public static int Main(string[] args)
    {
        var srcPpm = args.Length > 0 ? args[0] : null;
        var outDir = args.Length > 1 ? args[1] : ".";
        var display = new SharpMipDisplay(null);

        if (srcPpm != null)
        {
            ReplayFrame(display, srcPpm);
        }

        display.HarnessRepaint();
        display.DumpCanvas(Path.Combine(outDir, "canvas.ppm"));
        display.DumpFrame(Path.Combine(outDir, "frame.ppm"));

        // Press BTN2 (STOP, mid-left) through the pointer path the analyzer
        // window uses, so the pressed treatment is reviewable too.
        var pressed = new SharpMipDisplay(null, new NullGpio());
        if (srcPpm != null)
        {
            // Same frame again so the pressed shot shows a real page.
            ReplayFrame(pressed, srcPpm);
        }
        pressed.MoveTo(30, pressed.MaxY / 2);
        pressed.Press(Antmicro.Renode.Peripherals.Input.MouseButton.Left);
        pressed.HarnessRepaint();
        pressed.DumpCanvas(Path.Combine(outDir, "canvas-pressed.ppm"));
        Console.WriteLine("dumped canvas.ppm + frame.ppm + canvas-pressed.ppm");
        return 0;
    }

    private sealed class NullGpio : Antmicro.Renode.Peripherals.IGPIOReceiver
    {
        public void OnGPIO(int number, bool value)
        {
        }
    }

    // CS high, mode byte, then [addr][21 bytes][trailer] per line, CS low
    // closes + decodes. Wire bit 1 = white, bit 0 is leftmost of its group.
    private static void ReplayFrame(SharpMipDisplay display, string srcPpm)
    {
        var (w, h, rgb) = ReadPpm(srcPpm);
        if (w != 168 || h != 144)
        {
            throw new InvalidDataException($"expected 168x144, got {w}x{h}");
        }
        display.OnGPIO(0, true);
        display.Transmit(0x01);
        for (var y = 0; y < 144; y++)
        {
            display.Transmit((byte)(y + 1));
            for (var gx = 0; gx < 21; gx++)
            {
                byte b = 0;
                for (var bit = 0; bit < 8; bit++)
                {
                    var x = gx * 8 + bit;
                    if (rgb[(y * 168 + x) * 3] >= 128)
                    {
                        b |= (byte)(1 << bit);
                    }
                }
                display.Transmit(b);
            }
            display.Transmit(0x00);
        }
        display.Transmit(0x00);
        display.OnGPIO(0, false);
    }

    private static (int, int, byte[]) ReadPpm(string path)
    {
        using var s = File.OpenRead(path);
        string Token()
        {
            var t = "";
            int c;
            while ((c = s.ReadByte()) != -1)
            {
                if (char.IsWhiteSpace((char)c))
                {
                    if (t.Length > 0) break;
                    continue;
                }
                t += (char)c;
            }
            return t;
        }
        if (Token() != "P6") throw new InvalidDataException("not P6");
        var w = int.Parse(Token());
        var h = int.Parse(Token());
        Token(); // maxval
        var rgb = new byte[w * h * 3];
        var read = 0;
        while (read < rgb.Length)
        {
            var n = s.Read(rgb, read, rgb.Length - read);
            if (n <= 0) throw new EndOfStreamException();
            read += n;
        }
        return (w, h, rgb);
    }
}
