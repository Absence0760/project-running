# watch_garmin — local testing

Connect IQ is a vendor toolchain: not Melos, not npm, not Gradle, and there is
**no dnf or Flatpak package** (snap is forbidden on this workstation anyway).
You install Garmin's SDK Manager, which fetches the SDK + device simulators.

## 1. Install the Connect IQ SDK (one-time)

1. Sign in with a free Garmin developer account and download the **SDK Manager**
   from the official page: <https://developer.garmin.com/connect-iq/sdk/>.
   (It's a small Java app; the workstation already has a JDK from the Android
   toolchain. Verify with `java -version` — needs 8+.)
2. Run the SDK Manager, accept the licence, and let it install the **latest
   stable SDK** plus the **device simulators** for the products listed in
   `manifest.xml` (fenix7, epix2, fr955/965, venu2, …).
3. Add the SDK `bin/` to PATH so `monkeyc`, `monkeydo`, and `connectiq` are on
   the shell. Per this machine's conventions that's a guarded snippet in
   `~/.bashrc.d/15-connectiq.sh`:

   ```sh
   CIQ_HOME="$HOME/.Garmin/ConnectIQ/Sdks/current"
   [ -d "$CIQ_HOME/bin" ] && export PATH="$CIQ_HOME/bin:$PATH"
   ```

   (The SDK Manager symlinks the active SDK to `…/Sdks/current`. Adjust if your
   install path differs.)

## 2. Generate a developer key (one-time)

Every Connect IQ app is signed. Create a key once and keep it **out of git**
(`.gitignore` already excludes `developer_key` / `*.der` / `*.pem`):

```
openssl genrsa -out developer_key.pem 4096 && openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key -nocrypt
```

In VS Code (Garmin "Monkey C" extension) the command palette has
**"Connect IQ: Generate a Developer Key"** which does the same thing.

## 3. Build + run in the simulator

From this directory:

```
monkeyc -f monkey.jungle -o bin/RunGap.prg -y developer_key -d fenix7
```

Then launch the simulator and load the build:

```
connectiq && monkeydo bin/RunGap.prg fenix7
```

In the simulator: **Simulation → Activity Data → start a Run**, then assign the
field to a data cell (the field label is **GAP**). Use **Simulation → FIT Data
playback** (or the activity simulator's altitude/speed controls) to feed
altitude + speed so the grade adjustment moves. On flat input GAP tracks raw
pace; on a simulated climb GAP reads faster than raw pace, on a descent slower.

The VS Code extension wraps all of the above: **"Connect IQ: Build for Device"**
and **"Connect IQ: Run App"** with a device picker.

## 4. Sideload to a real watch (optional)

Build for the exact device (`-d fenix7x`, etc.), connect the watch over USB,
and copy the `.prg` to `GARMIN/APPS/` on the watch's mass-storage volume, or use
the extension's **"Connect IQ: Run on Device"**. The watch shows it under the
activity's data-field picker.

## 5. What to verify

- **Flat ground** → GAP equals native pace (factor ≈ 1.0).
- **Climb** → GAP faster than raw pace; **descent** → slower. Both clamp at
  ±45% grade (Minetti model's valid range).
- **Stopped / walking** (< 0.4 m/s) → field shows `--:--`, never a garbage
  number or a divide-by-zero.
- **Metric vs statute**: change the simulated device's units; pace unit
  (min/km vs min/mi) follows `System.getDeviceSettings().distanceUnits`.

## Not wired up yet

No CI job builds this (no `monkeyc` on the GitHub runners). No Supabase sync —
the field only reads on-watch `Activity.Info`. Both are deliberate for the
spike; see [CLAUDE.md](CLAUDE.md) for the path each would take.
