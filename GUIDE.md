# SongTop: Complete User Guide

Welcome to **SongTop**! This guide walks you through getting the most out of your native macOS YouTube Now Playing & Google Calendar companion.

---

## 1. Installation

1. Download `SongTop.zip` or clone this repository and run `./build_app.sh`.
2. Drag `SongTop.app` to your `/Applications` directory.
3. Open `SongTop.app`.

### Resolving macOS Gatekeeper Warnings
Because SongTop is an independent open-source macOS utility:
- **First Open**: Control-click (or right-click) `SongTop.app` in `/Applications`, select **Open**, and click **Open** in the dialog.
- Alternatively, run this terminal command:
  ```bash
  xattr -cr /Applications/SongTop.app
  ```

---

## 2. Stealth Background Operation

SongTop is designed to be invisible until you need it:
- **No Dock Icon**: SongTop does not show in the macOS Dock, keeping your Dock reserved for your active working apps.
- **Menu Bar Access**: Click the equalizer icon in the menu bar at any time to check track status or open settings.
- **Spotlight Activation**: Press `Cmd + Space`, type `SongTop`, and press `Enter` to bring up the Settings window.

---

## 3. Right-Edge Hover Panel

Move your mouse cursor towards the right edge of your screen:
- The companion panel smoothly slides out with a fast-entry decelerating ease-out curve.
- It displays currently detected YouTube media, companion video playback, and your daily schedule.
- When you move your cursor away, the panel retracts smoothly into the edge.
- If you prefer the panel to stay on screen permanently, click the **Pin** icon at the top right of the panel.

---

## 4. Enabling Browser Automation (Optional for Enhanced Controls)

SongTop automatically detects video titles from browser tabs. To enable zero-latency media control (play/pause, skip track, time synchronization):
- **Google Chrome / Brave / Arc**:
  Go to menu bar: `View` > `Developer` > check `Allow JavaScript from Apple Events`.
- **Safari**:
  Go to `Safari` > `Settings` > `Advanced` > check `Show Develop menu in menu bar`.
  Then in menu bar: `Develop` > check `Allow JavaScript from Apple Events`.

---

## 5. Google Calendar & Custom Class Detectors

SongTop categorizes your calendar events into three views:
- **Classes**: Dedicated tab for academic lectures, discussions, and labs.
- **Today**: All schedule items for today.
- **Tomorrow**: Preview of tomorrow's schedule.

### Setting Up Class Detectors:
1. Open **SongTop Settings & Customization**.
2. Scroll to the **Google Calendar Activity Panel** section.
3. In the **Class Detectors** field, enter your identifiers separated by commas:
   ```
   Class IEL, Alfatih, Lecture, Lab
   ```
4. Any calendar event with a title containing any of these keywords will immediately be routed to the **Classes** tab.

### Expanding Event Details:
- Click any calendar event card to view:
  - Date and time span
  - Location
  - Description / notes
  - One-click button to open in Google Calendar or Google Meet

---

## 6. Customizing Themes, Colors & Futuristic Fonts

1. Open **SongTop Settings & Customization**.
2. In the **Appearance, Color Scheme & Typography** card:
   - **Accent Colors**: Click preset buttons for **Orange**, **Coral**, **Blue**, **Green**, or **Purple**, or click the color well to select any custom hex color.
   - **Time Font**: Select between `Alien League Condensed`, `Alien League Regular`, `Futura Condensed Light`, `SF Pro Rounded Light`, or `Monospaced Digit`.
   - **App Font**: Select between `SF Pro Rounded (Default)`, `System Default`, `Monospaced`, or `Serif`.
- All changes update immediately across the entire app without requiring a restart.

---

## 7. Starting Automatically at Login

To make SongTop feel like a built-in macOS feature:
1. Open **SongTop Settings & Customization**.
2. In the **System & Menu Bar Integration** card, check **Launch SongTop automatically at login**.
3. SongTop will start silently in the background whenever your Mac turns on or logs in.
