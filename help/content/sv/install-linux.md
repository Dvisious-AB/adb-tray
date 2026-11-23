---
id: install-linux
title: Installera i Linux Mint
summary: Lägg till vårt apt-förråd och installera Appninjas ADB med uppdateringar.
icon: package
keywords: [installera, linux, mint, ubuntu, debian, apt, paket, förråd, installation, instalera]
sections: [add-repository, install, start, if-it-fails]
status: published
audience: [office]
public: true
minutes: 5
updated: 2026-11-23
---

Du lägger till vårt förråd en gång. Sedan uppdateras Appninjas ADB med resten av systemet. Det tar ungefär fem minuter.

## Lägg till förrådet {#add-repository}

1. Öppna Terminal.
2. Klistra in de här raderna och tryck på Retur:

```
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://dvisious-ab.github.io/adb-tray/appninjas-archive-keyring.gpg | sudo tee /etc/apt/keyrings/appninjas-archive-keyring.gpg >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/appninjas-archive-keyring.gpg] https://dvisious-ab.github.io/adb-tray stable main" | sudo tee /etc/apt/sources.list.d/appninjas.list
```

3. Skriv ditt lösenord när Terminal frågar efter det.

## Installera {#install}

4. Skriv `sudo apt update && sudo apt install adb-tray` och tryck på Retur.
5. Svara **J** när apt frågar om du vill fortsätta.

Paketet installerar också :term[adb] och :term[scrcpy].

## Starta Appninjas ADB {#start}

6. Öppna programmenyn och välj **Appninjas ADB**.
7. Titta i :term[systemfältet]. Ikonen är en telefon.

Appninjas ADB startar nu också varje gång du loggar in.

## Om det inte fungerar {#if-it-fails}

Om ikonen inte syns: läs [Lös vanliga problem](help:troubleshooting#no-icon).
