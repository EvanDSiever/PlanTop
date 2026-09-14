# SongTop

<p align="center">
  <img src="Assets/app_icon.jpg" width="128" height="128" alt="SongTop App Icon" style="border-radius: 26px; box-shadow: 0 10px 25px rgba(0,0,0,0.15);" />
</p>

<h3 align="center">A Native, Stealth macOS Side-Panel Companion for YouTube Now Playing & Google Calendar</h3>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2013%2B-000000?style=flat-square&logo=apple" alt="macOS 13+" />
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20%2F%20Universal-blue?style=flat-square" alt="Apple Silicon" />
  <img src="https://img.shields.io/badge/Language-Swift%206-orange?style=flat-square&logo=swift" alt="Swift 6" />
  <img src="https://img.shields.io/badge/UI-Native%20AppKit-red?style=flat-square" alt="Native AppKit" />
  <img src="https://img.shields.io/badge/Appearance-White%20%26%20Orange-orange?style=flat-square" alt="White and Orange" />
</p>

---

## What is SongTop?

**SongTop** is a lightweight, stealth macOS background utility built in pure Swift and AppKit. It integrates directly into macOS without cluttering your Dock, providing:

1. **Right-Edge Hover Side Panel**: Move your cursor to the right edge of your screen to smoothly slide out your media companion and daily calendar.
2. **YouTube Now Playing & PiP**: Automatically detects YouTube and YouTube Music playback from any running browser (Google Chrome, Safari, Brave, Arc, Microsoft Edge, Opera, Vivaldi), featuring live video playback and audio-video lip-sync calibration.
3. **Google Calendar Activity Hub**: View your schedule organized cleanly across **Classes**, **Today**, and **Tomorrow** tabs.
4. **Custom Class Detectors**: Define custom keywords (e.g. `Class IEL, Alfatih`) to automatically categorize lectures, labs, and academic events.
5. **Futuristic Typography & White-Orange Theme**: Signature vibrant orange accents with large futuristic time badges (Alien League, Futura) and clean borderless white ceramic card surfaces.

---

## Quick Start & Download

### Option 1: Download Prebuilt Release
1. Download **[SongTop.zip](SongTop.zip)**.
2. Unzip the file to reveal `SongTop.app`.
3. Drag `SongTop.app` into your `/Applications` folder.
4. **First Launch**:
   - Double-click `SongTop.app` in `/Applications` (or search for **SongTop** in Spotlight).
   - If prompted by macOS Gatekeeper, right-click (or Control-click) `SongTop.app` and choose **Open**, then click **Open**.
   - Alternatively, remove the quarantine attribute via Terminal:
     ```bash
     xattr -cr /Applications/SongTop.app
     ```

### Option 2: Build from Source
```bash
git clone https://github.com/EvanDSiever/SongTop.git
cd SongTop
./build_app.sh
```
This generates the compiled `.app` bundle at `./SongTop.app` and distribution package at `./SongTop.zip`.

---

## How to Use SongTop

### 1. Seamless Background Integration (No Dock Icon)
SongTop runs as a native macOS **Accessory (`LSUIElement`)**. It never takes up space in your macOS Dock, keeping your workspace clean and distraction-free.

### 2. Accessing SongTop
- **Menu Bar**: Look for the equalizer icon in the top right menu bar. Click it to view current track info, change modes, or click **SongTop Settings & Customization...**.
- **Spotlight Search**: Press `Cmd + Space`, type `SongTop`, and press `Enter` to open the Settings window at any time.

### 3. Right-Edge Hover Panel
- Move your mouse cursor towards the right edge of your display.
- The companion panel smoothly slides out with a high-velocity ease-out deceleration curve.
- Hover away to let it retract automatically, or click the pin button to keep it fixed.

### 4. YouTube Audio & Video Detection
- Play any video or song on YouTube / YouTube Music in your browser.
- Supported browsers:
  - **Google Chrome**
  - **Safari**
  - **Brave Browser**
  - **Arc Browser**
  - **Microsoft Edge**
- *Tip for direct in-tab media controls*: Enable Apple Events JavaScript in your browser (e.g., in Chrome: `View > Developer > Allow JavaScript from Apple Events`).

### 5. Google Calendar & Custom Class Detectors
- In **Settings & Customization**, link your Google Calendar account or grant Calendar access.
- In the **Class Detectors** field, enter keywords separated by commas (e.g., `Class IEL, Alfatih, Lecture`).
- Any calendar event with matching keywords automatically routes to your dedicated **Classes** tab.
- Click any event card in the panel to expand its details (date, time span, location, notes, and direct Google Calendar/Meet link).

### 6. Appearance & Color Customization
- Open Settings to customize:
  - **Accent Colors**: Orange (`#FF700D`), Coral, Blue, Green, Purple, or pick custom colors using the native color picker.
  - **Time Font**: Choose between Alien League Condensed, Alien League Regular, Futura Condensed Light, SF Pro Rounded, and Monospaced.
  - **App Typography**: Toggle between SF Pro Rounded, System Default, Monospaced, and Serif.

### 7. Run at Startup (Launch at Login)
- Open SongTop Settings.
- Under **System & Menu Bar Integration**, check **Launch SongTop automatically at login**.
- SongTop will start silently in the background on every Mac boot without popping up any windows.

---

## Keyboard & Window Shortcuts

| Action | Shortcut / Method |
| :--- | :--- |
| **Open Settings** | Search "SongTop" in Spotlight or click Menu Bar icon |
| **Toggle Full Screen** | `Control + Command + F` (or click green traffic light) |
| **Peek Side Panel** | Click "Test Side Panel" in Settings |
| **Quit App** | Menu Bar icon > Quit SongTop |

---

## Requirements
- **macOS**: 13.0 (Ventura) or later (macOS Sonoma & Sequoia fully supported).
- **Architecture**: Apple Silicon (M1/M2/M3/M4) & Intel Universal.

---

## License
MIT License. Created by Evan Siever.
