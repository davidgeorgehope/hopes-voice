# Run BestWishes on a real iPad

USB debug run from a Mac is enough for a playtest. You do not need an App Store or TestFlight slot just to install a development build. Store distribution is a later, separate track (see the `store-readiness` issues).

| | |
|---|---|
| Xcode project | `ios/BestWishes/BestWishes.xcodeproj` |
| Scheme | `BestWishes` |
| Run configuration | **Debug** |
| Archive configuration | **Release** (optional) |
| Bundle ID | `love.bestwishes.app` |
| Team | your team (Automatic signing) |
| Deploy target | iOS 18.0 |
| Device family | iPad only today (`TARGETED_DEVICE_FAMILY = 2`); iPhone support is on the roadmap |
| API | `https://bestwishes.love` — the device needs network **once** to warm `GET /v1/board` and cache pictures and spoken audio, then Speak works offline |

The checked-in project leaves `DEVELOPMENT_TEAM` empty so each developer selects their own team in Xcode.

---

## 1. USB Run

### In Xcode

1. Plug the iPad in with USB. Unlock it. If it asks **Trust This Computer**, tap Trust and enter the passcode.
2. On iPadOS 16+, turn on **Developer Mode**: Settings → Privacy & Security → Developer Mode → On, then restart when asked.
3. Open the project:

   ```bash
   open ios/BestWishes/BestWishes.xcodeproj
   ```

4. In the scheme/destination menu, pick scheme **BestWishes** and the **physical iPad** (not a Simulator).
5. If Xcode offers to register the device with your team, allow it (Automatic signing).
6. Press **Run** (⌘R).
7. First launch on a new device: if the iPad shows **Untrusted Developer**, go to Settings → General → VPN & Device Management → Apple Development → Trust.

The iPad must be able to reach `https://bestwishes.love` **once** so `GET /v1/board` can fill the grid and cache pictures and MP3s. After that, Speak works offline. The app never calls xAI.

### From the terminal

List destinations (the iPad appears as `{ platform:iOS, id:<device-id>, name:… }`, not `iOS Simulator`):

```bash
xcodebuild -project ios/BestWishes/BestWishes.xcodeproj -scheme BestWishes -showdestinations
```

Build and install onto that iPad (`<device-id>` from the line above):

```bash
xcodebuild \
  -project ios/BestWishes/BestWishes.xcodeproj \
  -scheme BestWishes \
  -configuration Debug \
  -destination 'id=<device-id>' \
  -allowProvisioningUpdates \
  build
```

You can also install a built `.app` with `xcrun devicectl` when the iPad is reachable from the Mac. An automated watcher that retries that path is planned; it is not set up in this repo yet.

Xcode ⌘R is the simpler path; it uses the same scheme, Debug configuration, and Automatic signing.

---

## 2. Optional Archive

USB Run is enough for a playtest. Skip this unless you want an `.xcarchive` on disk. Development or Ad Hoc export is for devices registered to your team. App Store Connect / TestFlight uploads belong to the store-readiness work, not to a local debug run.

```bash
xcodebuild \
  -project ios/BestWishes/BestWishes.xcodeproj \
  -scheme BestWishes \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$HOME/Library/Developer/Xcode/Archives/BestWishes.xcarchive" \
  archive
```

Set your team in Xcode (or pass `DEVELOPMENT_TEAM=<your team>`) before archiving.

---

## 3. First-launch checklist

Do this on the physical iPad after ⌘R, with the network **on** for steps 1–5.

1. **Unlock caregiver** (long-press title). Long-press the **Best Wishes** title for about **1.5 seconds**. The Add bar, Lock, profile switcher, and a small Caregiver label appear. Kid mode is the default on a first launch with no saved choice.
2. **Pick a profile.** Default names are **Child 1** and **Child 2**. On the caregiver Add row, tap the other name. The badge under the title is the active profile. First launch with no saved choice is Child 1. Caregivers can rename profiles once that setting ships.
3. **Warm the board.** Stay online until the grid fills from `GET /v1/board` at `https://bestwishes.love`. Pictures and spoken MP3s download into the on-device cache. The app never calls xAI.
4. **Tap cores.** The sticky row is **I / want / more / help / stop / go**. Each tap appends a chip to the sentence strip and plays that word’s cached MP3.
5. **Speak the strip.** Tap **Speak** on the strip. It plays every chip’s cached MP3 in order.
6. **Airplane-mode Speak smoke.** Turn on Airplane Mode (or otherwise drop the network). Tap cores or board cards again, then **Speak**. Cached MP3s must still play. A failed `GET /v1/board` must **not** wipe the grid. Caregiver Add / Folder / Delete will error without the server — that is expected.

Lock again with **Lock** before a child uses the board.

Live caregiver dictation (voice-add) also needs a real device; the Simulator has no microphone.
