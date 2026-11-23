---
id: troubleshooting
title: Solve common problems
summary: What to do when the icon is missing, adb is missing or mirroring closes.
icon: wrench
keywords: [problem, error, not working, help, icon missing, adb missing, offline, not responding, stuck]
sections: [no-icon, adb-missing, unauthorized, mirroring-closes, stuck]
status: published
audience: [office]
public: true
minutes: 3
updated: 2026-11-23
---

These are the most common problems and what to do about them.

## The icon does not appear {#no-icon}

On a Mac, a full menu bar can hide icons behind the camera. Quit another app with a menu bar icon. If the icon is still missing: type `brew services restart adb-tray` in Terminal.

On Linux Mint the panel shows the icon through the **Xapp Status Applet**. Add it to the panel if it is missing.

## The menu says adb is not installed {#adb-missing}

On a Mac: click :button[menu.copyInstall]{icon=copy} in the menu. Paste the command into Terminal and press Return.

On Linux Mint: type `sudo apt install adb` in Terminal.

## The device is waiting for permission {#unauthorized}

The device is shown with :button[device.unauthorized]. Tap **Allow** on the device. If no dialog appears: choose **Revoke USB debugging authorisations** under Developer options and plug the cable in again.

## Mirroring closes at once {#mirroring-closes}

The message shows the location of the log file. Some devices cannot handle full resolution. Start mirroring again. If that does not help, send us the log file.

## Everything seems to have stopped {#stuck}

Click :button[menu.restartServer]{icon=power} in the menu. Wait a few seconds and click :button[menu.refresh].
