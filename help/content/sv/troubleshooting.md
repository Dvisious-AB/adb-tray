---
id: troubleshooting
title: Lös vanliga problem
summary: Vad du gör när ikonen saknas, adb saknas eller speglingen stängs.
icon: wrench
keywords: [problem, fel, fungerar inte, hjälp, ikon saknas, adb saknas, offline, svarar inte, hänger sig]
sections: [no-icon, adb-missing, unauthorized, mirroring-closes, stuck]
status: published
audience: [office]
public: true
minutes: 3
updated: 2026-11-23
---

Här står de vanligaste problemen och vad du gör åt dem.

## Ikonen syns inte {#no-icon}

På en Mac kan en full menyrad dölja ikoner bakom kameran. Stäng ett annat program med ikon i menyraden. Om ikonen ändå saknas: skriv `brew services restart adb-tray` i Terminal.

I Linux Mint visar panelen ikonen via appleten **Xapp Status Applet**. Lägg till den i panelen om den saknas.

## Menyn säger att adb saknas {#adb-missing}

På en Mac: klicka på :button[menu.copyInstall]{icon=copy} i menyn. Klistra in kommandot i Terminal och tryck på Retur.

I Linux Mint: skriv `sudo apt install adb` i Terminal.

## Enheten väntar på godkännande {#unauthorized}

Enheten visas med :button[device.unauthorized]. Tryck på **Tillåt** på enheten. Om ingen dialogruta syns: välj **Återkalla behörigheter för USB-felsökning** under Utvecklaralternativ och anslut kabeln igen.

## Speglingen stängs direkt {#mirroring-closes}

Meddelandet visar var loggfilen ligger. Vissa enheter klarar inte full upplösning. Starta speglingen igen. Hjälper det inte, skicka loggfilen till oss.

## Allt verkar ha stannat {#stuck}

Klicka på :button[menu.restartServer]{icon=power} i menyn. Vänta några sekunder och klicka på :button[menu.refresh].
