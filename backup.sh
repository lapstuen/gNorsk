#!/bin/bash
claude --prompt "🔴 KRITISK - LES DETTE FØRST:

1. Ta FULL backup av hele prosjektet til ~/Backups/gThai_$(date +%Y%m%d_%H%M%S)
2. Bekreft at backup er fullført
3. Si BARE at backup er tatt - IKKE start på noe arbeid
4. VENT på mitt neste prompt hvor jeg vil gi deg den faktiske oppgaven (med lengre beskrivelser, bilder, etc)

GJØR INGENTING annet enn backup!"
