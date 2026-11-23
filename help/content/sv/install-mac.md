---
id: install-mac
title: Installera på en Mac
summary: Installera Appninjas ADB med Homebrew och starta det vid inloggning.
icon: download-simple
keywords: [installera, mac, macos, homebrew, brew, ladda ner, installation, instalera]
sections: [you-need, install, start, if-it-fails]
status: published
audience: [office]
public: true
minutes: 10
updated: 2026-11-23
---

Du installerar Appninjas ADB med ett par kommandon. Det tar ungefär tio minuter, mest väntan.

## Det här behöver du {#you-need}

:::need
- En Mac med macOS 13 Ventura eller senare.
- :term[Homebrew], installerat från brew.sh.
- Xcode från App Store. Homebrew bygger appen på din Mac.
:::

## Installera {#install}

1. Öppna :term[Terminal].
2. Klistra in de här kommandona och tryck på Retur:

```
brew install --cask android-platform-tools
brew install dvisious-ab/tap/adb-tray
```

3. Vänta tills Terminal visar en ny rad att skriva på. Det tar några minuter.

Det första kommandot installerar :term[adb]. Det andra installerar Appninjas ADB och :term[scrcpy].

## Starta Appninjas ADB {#start}

4. Skriv `brew services start adb-tray` och tryck på Retur.
5. Titta i :term[menyraden]. Ikonen är en telefon.

Appninjas ADB startar nu också varje gång du loggar in.

## Om det inte fungerar {#if-it-fails}

Om Terminal säger att Xcode saknas: installera Xcode från App Store och kör kommandona igen.

Om ikonen inte syns: läs [Lös vanliga problem](help:troubleshooting#no-icon).
