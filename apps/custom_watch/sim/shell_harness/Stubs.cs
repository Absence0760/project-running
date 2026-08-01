// Minimal stand-ins for the Antmicro.Renode types SharpMipDisplay.cs touches,
// so the model compiles + renders on a host with no Renode install. Only the
// API surface the model already uses is stubbed — adding a new Renode call to
// the model means teaching this file about it first, which is the point: the
// harness fails where the runtime compile would.

using System;

namespace Antmicro.Renode.Core
{
    public interface IMachine { }
}

namespace Antmicro.Renode.Logging
{
    public enum LogLevel { Noisy, Debug, Info, Warning, Error }

    public static class LoggingExtensions
    {
        public static void Log(this object o, LogLevel level, string format, params object[] args)
        {
        }
    }
}

namespace Antmicro.Renode.Backends.Display
{
    public enum PixelFormat { RGB888 }
}

namespace Antmicro.Renode.Peripherals.SPI
{
    public interface ISPIPeripheral
    {
        byte Transmit(byte data);
        void FinishTransmission();
    }
}

namespace Antmicro.Renode.Peripherals.Input
{
    public enum MouseButton { Left, Right, Middle }

    public interface IAbsolutePositionPointerInput
    {
        int MaxX { get; }
        int MaxY { get; }
        int MinX { get; }
        int MinY { get; }
        void MoveTo(int x, int y);
        void Press(MouseButton button);
        void Release(MouseButton button);
    }
}

namespace Antmicro.Renode.Peripherals
{
    public interface IGPIOReceiver
    {
        void OnGPIO(int number, bool value);
    }
}

namespace Antmicro.Renode.Peripherals.Video
{
    using Antmicro.Renode.Backends.Display;
    using Antmicro.Renode.Core;

    public abstract class AutoRepaintingVideo
    {
        protected AutoRepaintingVideo(IMachine machine)
        {
        }

        protected byte[] buffer;

        protected void Reconfigure(int width, int height, PixelFormat format)
        {
            buffer = new byte[width * height * 3];
        }

        public virtual void Reset()
        {
        }

        protected abstract void Repaint();

        // Harness-only trigger; Renode calls Repaint on its own timer.
        public void HarnessRepaint()
        {
            Repaint();
        }
    }
}
