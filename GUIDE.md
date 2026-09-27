# PlanTop: Complete User Guide

Welcome to **PlanTop**! This guide walks you through getting the most out of your native macOS stealth daily planner & Google Calendar companion.

---

## 1. Installation

1. Download `PlanTop.zip` or clone this repository and run `./build_app.sh`.
2. Drag `PlanTop.app` to your `/Applications` directory.
3. Open `PlanTop.app`.

### Resolving macOS Gatekeeper Warnings
Because PlanTop is an independent open-source macOS utility:
- **First Open**: Control-click (or right-click) `PlanTop.app` in `/Applications`, select **Open**, and click **Open** in the dialog.
- Alternatively, run this terminal command:
  ```bash
  xattr -cr /Applications/PlanTop.app
  ```

---

## 2. Stealth Background Operation

PlanTop is designed to stay completely out of your way until you need it:
- **No Dock Icon**: PlanTop operates as a macOS accessory (`LSUIElement`) and does not appear in the Dock, reserving your dock space for primary apps.
- **Menu Bar Access**: Look for the calendar-clock icon in the top right macOS menu bar. Click it to view today's upcoming events, sync status, or open settings.
- **Spotlight Activation**: Press `Cmd + Space`, type `PlanTop`, and press `Enter` to bring up the Settings window at any time.

---

## 3. Right-Edge Hover Panel

Move your mouse cursor towards the right edge of your screen:
- The daily planner panel smoothly slides out with a fast-entry decelerating ease-out curve.
- It displays your live date and futuristic digital clock, current countdowns, and daily schedule cards.
- When you move your cursor away, the panel retracts smoothly into the edge.
- If you prefer the panel to stay on screen permanently, click the **Pin** icon at the top right of the panel.
- Drag the left edge of the panel to dynamically resize the width from 260px to 650px.

---

## 4. Google Calendar & Custom Class Detectors

PlanTop organizes your events into four focused views:
- **Classes**: Dedicated tab for lectures, discussions, labs, and academic sessions.
- **Tasks**: Dedicated tab for assignments, reports, and homework starting with `REPORT` or `HOMEWORK` prefixes, strictly focused on the current week (Monday 00:00:00 through Sunday 23:59:59). For tasks happening or due on the current day, live second-by-second countdown timers (`Starts in ...`, `Ends in ...`, `Ended`) are displayed. For tasks scheduled later in the week, the date of occurrence (e.g. `Friday, Sep 25`, `Saturday, Sep 26`) is displayed directly underneath the title without timer clutter. Recurring and repeated tasks across weeks (such as weekly laboratory reports) are strictly deduplicated so only the current week's upcoming instance is shown.
- **Today**: All general schedule items for today with active status badges (`[NOW]`, `In 15m`).
- **Tomorrow**: Preview of tomorrow's schedule.

### Setting Up Class Detectors:
1. Open **PlanTop Settings & Preferences**.
2. Under **Daily Planner & Google Calendar Integration**, find the **Class Detectors** field.
3. Enter your identifiers separated by commas:
   ```
   Class IEL, Alfatih, Lecture, Lab, Seminar
   ```
4. Any calendar event with a matching title is automatically routed to the **Classes** tab.

### Expanding Event Details:
- Click any calendar event card to view:
  - Date and time span
  - Location
  - Description / notes
  - One-click button to launch Google Meet, Zoom, or Teams
  - Direct button to view in the macOS Calendar app

---

## 5. Instant Quick Notes with Rich Formatting & Markdown Lists

Directly below the large clock and calendar panel is the **Instant Quick Notes** surface:
- **Instant Writing**: The header bar and title have been eliminated so clicking anywhere immediately focuses the text editor with zero friction.
- **Larger 14.5pt Typography**: Clear, highly legible Avenir text sizing with comfortable line spacing.
- **Smart Bullet & Numbered Lists**:
  - Type `- `, `* `, or `• ` to start a bullet list. Pressing `Return` automatically continues the list. Pressing `Return` on an empty bullet line cleanly exits the list.
  - Type `1. ` to start a numbered list. Pressing `Return` automatically increments numbers (`2. `, `3. `). Pressing `Return` on an empty numbered line exits the list.
  - Or click the **`•` (Bullet)** and **`1.` (Numbered)** buttons in the bottom toolbar to toggle lists on your current selection.
- **Bold & Italic Formatting**:
  - Wrap words in `**bold**` or `*italic*` syntax.
  - Use keyboard shortcuts `Cmd + B` for bold and `Cmd + I` for italic, or click the **B** and **I** toolbar buttons.
  - Enjoy live visual syntax styling right inside the note editor.
- **Persistent Storage**: Notes are preserved automatically in `UserDefaults` across app launches. Click the subtle trash icon in the toolbar when you want to clear your notes.

---

## 6. Customizing Themes, Colors & Apple Typography
 
1. Open **PlanTop Settings & Preferences**.
2. In the **Appearance, Color Scheme & Typography** card:
   - **Accent Colors**: Select between Apple system colors (**Blue**, **Purple**, **Green**, **Orange**, **Red**), or use the native color picker for custom tones.
   - **Time Font**: Choose between `SF Pro Monospaced Digits (Default)`, `SF Pro Rounded`, `SF Mono`, `Futura Condensed Light`, or `Alien League`.
   - **App Font**: Choose between `SF Pro (System Default)`, `SF Pro Rounded`, `SF Mono`, `Avenir`, or `System Serif`.
- All theme updates reflect instantly across the side panel and menu bar.

---

## 7. Starting Automatically at Login

To have PlanTop ready on your desktop whenever you start your Mac:
1. Open **PlanTop Settings & Preferences**.
2. Under **System & Menu Bar Integration**, check **Launch PlanTop automatically at login**.
3. PlanTop will start silently in the background on every Mac boot without popping up any intrusive windows.
