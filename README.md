# 🚨 Goalhorn

An iPhone app that turns scoring in your living room into an arena moment. Tap
the big goal light and Goalhorn will:

- **Spin your HomeKit lights** like a rotating arena goal beacon — red/blue
  sweeping around the room, then everything returns exactly to how it was.
- **Blast your goal song** on your **Sonos** speaker (or the phone itself).

You bring your own goal song (upload any audio file) and your own smart lights.

<p align="center"><em>Tap the light → GOOOAL!</em></p>

---

## What's in the box

| Tab | What it does |
| --- | --- |
| **Goal** | A giant animated goal light. Tap it to fire the celebration; a **Stop** button ends it early. |
| **Songs** | Upload goal songs (MP3/M4A/WAV/AIFF) and pick which one plays. |
| **Sonos** | Choose the output (Sonos vs. iPhone), scan your Wi‑Fi for Sonos players, set the volume. |
| **Lights** | Grant HomeKit access, choose which bulbs spin, set how long the show lasts, and run a **test**. |

## Requirements

- **Xcode 16** or newer (the project uses file‑system‑synchronized groups).
- **iOS 17** or newer.
- A **real iPhone** for the full experience. HomeKit and Sonos need a physical
  device on your home Wi‑Fi — the Simulator can't reach either.
- A **paid Apple Developer account** to enable the HomeKit capability (see
  below). The rest of the app runs with a free personal team.
- Color‑capable **HomeKit lightbulbs** already set up in Apple's Home app.
- A **Sonos** speaker on the same Wi‑Fi (optional — you can play on the phone).

## Getting started

1. Open `Goalhorn.xcodeproj` in Xcode.
2. Select the **Goalhorn** target → **Signing & Capabilities**:
   - Set your **Team**.
   - Change the **Bundle Identifier** to something unique to you, e.g.
     `com.yourname.Goalhorn`.
   - The **HomeKit** capability is already declared in
     `Goalhorn/Goalhorn.entitlements`. With a paid team, Xcode will register the
     App ID with HomeKit automatically. (Without HomeKit entitlement the app
     still builds and the audio side works; the Lights tab just won't find
     bulbs.)
3. Plug in your iPhone, pick it as the run destination, and press **Run**.
4. On first launch, grant:
   - **HomeKit** access (prompted when you open the **Lights** tab).
   - **Local Network** access (prompted when you scan for Sonos).

## Using it

1. **Songs** → *Upload a Goal Song* → import your horn/song. Tap it to select it.
2. **Sonos** → choose **Sonos speaker**, tap **Scan for Sonos**, pick your
   speaker, and set a volume. (Or choose **This iPhone** to skip Sonos.)
3. **Lights** → toggle on the bulbs you want spinning and set the duration.
4. **Goal** → tap the light. 🚨

## How it works

```
GoalScreen (tap)
      │
      ▼
CelebrationController ──► GoalLightEngine ──► HomeKit (spin bulbs, then restore)
      │
      ├─► Sonos path:  LocalAudioServer (hosts the file over HTTP)
      │                        │
      │                        ▼
      │                SonosController (UPnP/SOAP: SetAVTransportURI → Play)
      │
      └─► Phone path:  LocalAudioPlayer (AVAudioPlayer)
```

- **HomeKit** (`HomeKit/`): `HomeKitManager` surfaces your lightbulb services;
  `GoalLightEngine` snapshots each bulb, sweeps a bright "beam" around the
  selected bulbs while alternating red/blue, then restores the original state.
- **Sonos over the local network** (`Sonos/`): iOS blocks SSDP multicast without
  a special entitlement, so `SonosDiscovery` finds players by scanning your
  `/24` subnet for the Sonos description endpoint on port `1400`.
  `SonosController` then drives standard UPnP `AVTransport`/`RenderingControl`
  SOAP actions — no Sonos cloud account required.
- **Streaming the file to Sonos** (`Audio/LocalAudioServer.swift`): Sonos can't
  read the app sandbox, so the phone runs a tiny HTTP server (with byte‑range
  support) and hands Sonos a `http://<phone-ip>:<port>/…` URL to stream.
- **Persistence** (`Models/AppSettings.swift`): your chosen song, lights,
  speaker, volume, and duration are stored in `UserDefaults`; uploaded audio
  lives in Application Support.

### Project layout

```
Goalhorn/
├─ GoalhornApp.swift          App entry; wires up shared services
├─ Info.plist                 Usage strings (HomeKit, Local Network), background audio
├─ Goalhorn.entitlements      HomeKit capability
├─ Models/                    AudioTrack, AppSettings
├─ HomeKit/                   HomeKitManager, GoalLightEngine
├─ Audio/                     AudioLibrary, LocalAudioServer, LocalAudioPlayer
├─ Sonos/                     SonosModels, SonosDiscovery, SonosController
├─ Celebration/               CelebrationController (orchestrator)
├─ Utilities/                 NetworkInterface (Wi‑Fi IP / subnet)
└─ Views/                     ContentView, BeaconView, and the four tab screens
```

## Notes & limitations

- **Same Wi‑Fi network.** Both the iPhone and the Sonos/HomeKit devices must be
  on the same LAN. If a scan finds nothing, confirm Wi‑Fi and try the manual IP
  field on the Sonos tab.
- **Sonos discovery is a subnet scan.** It assumes a `/24` home network. If your
  speaker isn't found, enter its IP manually (find it in the Sonos app under
  *Settings → System → About My System*).
- **The song plays to its end.** The light show stops after the duration you
  set; the goal song keeps playing on Sonos until it finishes (or you hit Stop).
- **HomeKit write latency.** Bulbs update as fast as HomeKit allows; a handful of
  color bulbs give the smoothest spin.
- **No bundled audio or app icon art.** Bring your own goal song; the app icon
  slot is left empty for you to drop in artwork.

## Roadmap ideas

- Multiple saved goal presets (team‑specific songs + light colors).
- Apple Watch / widget / Siri Shortcut trigger ("Hey Siri, GOAL!").
- Grouping several Sonos rooms for a whole‑house horn.
