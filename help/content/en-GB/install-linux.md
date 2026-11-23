---
id: install-linux
title: Install on Linux Mint
summary: Add our apt repository and install Appninjas ADB with updates.
icon: package
keywords: [install, linux, mint, ubuntu, debian, apt, package, repository, installation, instal]
sections: [add-repository, install, start, if-it-fails]
status: published
audience: [office]
public: true
minutes: 5
updated: 2026-11-23
---

You add our repository once. After that, Appninjas ADB is updated with the rest of the system. It takes about five minutes.

## Add the repository {#add-repository}

1. Open Terminal.
2. Paste these lines and press Return:

```
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://dvisious-ab.github.io/adb-tray/appninjas-archive-keyring.gpg | sudo tee /etc/apt/keyrings/appninjas-archive-keyring.gpg >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/appninjas-archive-keyring.gpg] https://dvisious-ab.github.io/adb-tray stable main" | sudo tee /etc/apt/sources.list.d/appninjas.list
```

3. Type your password when Terminal asks for it.

## Install {#install}

4. Type `sudo apt update && sudo apt install adb-tray` and press Return.
5. Answer **Y** when apt asks whether to continue.

The package also installs :term[adb] and :term[scrcpy].

## Start Appninjas ADB {#start}

6. Open the application menu and choose **Appninjas ADB**.
7. Look in the :term[system tray]. The icon is a phone.

Appninjas ADB now also starts every time you log in.

## If it does not work {#if-it-fails}

If the icon does not appear: read [Solve common problems](help:troubleshooting#no-icon).
