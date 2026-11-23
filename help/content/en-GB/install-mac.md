---
id: install-mac
title: Install on a Mac
summary: Install Appninjas ADB with Homebrew and start it when you log in.
icon: download-simple
keywords: [install, mac, macos, homebrew, brew, download, installation, instal]
sections: [you-need, install, start, if-it-fails]
status: published
audience: [office]
public: true
minutes: 10
updated: 2026-11-23
---

You install Appninjas ADB with a couple of commands. It takes about ten minutes, mostly waiting.

## What you need {#you-need}

:::need
- A Mac with macOS 13 Ventura or later.
- :term[Homebrew], installed from brew.sh.
- Xcode from the App Store. Homebrew builds the app on your Mac.
:::

## Install {#install}

1. Open :term[Terminal].
2. Paste these commands and press Return:

```
brew install --cask android-platform-tools
brew install dvisious-ab/tap/adb-tray
```

3. Wait until Terminal shows a new line to type on. It takes a few minutes.

The first command installs :term[adb]. The second installs Appninjas ADB and :term[scrcpy].

## Start Appninjas ADB {#start}

4. Type `brew services start adb-tray` and press Return.
5. Look in the :term[menu bar]. The icon is a phone.

Appninjas ADB now also starts every time you log in.

## If it does not work {#if-it-fails}

If Terminal says that Xcode is missing: install Xcode from the App Store and run the commands again.

If the icon does not appear: read [Solve common problems](help:troubleshooting#no-icon).
