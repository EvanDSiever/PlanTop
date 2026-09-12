<p align="center">
  <img src="Assets/app_icon.jpg" width="140" height="140" alt="SongTop App Icon" style="border-radius: 28px;" />
</p>

<h1 align="center">SongTop</h1>

<p align="center">
  <b>A lightweight, native macOS software that displays the song or video you're currently listening to on YouTube (or YouTube Music) right at the top of your screen.</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2013%2B-black?style=flat-square&logo=apple" alt="macOS 13+" />
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20%2F%20Universal-blue?style=flat-square" alt="Apple Silicon" />
  <img src="https://img.shields.io/badge/Language-Swift%206-orange?style=flat-square&logo=swift" alt="Swift 6" />
  <img src="https://img.shields.io/badge/UI-Native%20AppKit-red?style=flat-square" alt="Native AppKit" />
</p>

---

## ✨ Features

- **Interactive Top-Screen Hover Dropdown**: Tucks discreetly into your top screen bezel / MacBook notch. Whenever you move your mouse to the center top of the screen (or when a new track begins), a sleek frosted-glass banner smoothly slides down to reveal the song, artist, live frequency waveforms, and quick action buttons!
- **Zero Configuration**: Works instantly out of the box with your running browsers:
  - **Google Chrome**
  - **Safari**
  - **Brave Browser**
  - **Arc Browser**
  - **Microsoft Edge**
  - **Opera** & **Vivaldi**
- **Cleans YouTube Titles**: Automatically strips YouTube notification badges (e.g. `(1)`, `(99+)`), play indicators (`▶`), and browser suffixes (`- YouTube`, `- YouTube Music`).
- **macOS Menu Bar Display**: Sits quietly in your macOS top menu bar with an animated equalizer icon and live track name.
- **Interactive Controls**:
  - **Focus Tab**: Click to bring the playing YouTube browser tab directly to the front.
  - **Copy Title**: Copy the formatted song name to your clipboard with one click.
  - **Play / Pause**: Toggle playback right from the menu.
  - **Next Track**: Skip to the next video or track in the playlist.
- **Ultra Lightweight & Fast**: Native Swift & AppKit Mach-O binary (<200KB binary, <0.2% CPU). Runs with `LSUIElement` to keep your Dock clean.

---

## 🚀 How to Run

### Prebuilt Application
Download or open the compiled bundle:
```bash
open SongTop.app
```

Or move it to your `/Applications` directory:
```bash
cp -R SongTop.app /Applications/
```

---

## 🛠️ Building from Source

### Prerequisites
- macOS 13.0 or later
- Swift 5.9+ / Swift 6 (Command Line Tools or Xcode)

### One-Click Build
Run the automated build script:
```bash
./build_app.sh
```
This compiles the native binary, builds the `.app` bundle structure with icons and `Info.plist`, and codesigns the app locally.

---

## ⚙️ Customization

Click on the SongTop icon in the macOS menu bar at any time to:
- Choose your preferred display mode:
  - **Drop Down on Top Hover** (Default: tucked at top edge, drops down when hovering or when a song changes)
  - **Always Keep Top Banner Visible** (stays pinned on screen)
  - **Hide Top Banner (Menu Bar Only)**
- Toggle showing the **Song Name in Menu Bar**.
- Manually refresh with **Check Now**.
- Quit SongTop.

---

## 📄 License
MIT License. Feel free to use, modify, and contribute!
