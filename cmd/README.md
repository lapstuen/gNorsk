# Git Kommandoer

Denne mappen inneholder kommandofiler som kan kjøres direkte fra Finder.

## Bruk

**Dobbeltklikk på `gitmenu.command` i Finder** for å åpne en interaktiv git-meny i Terminal.

Scriptet jobber automatisk i prosjektmappen (parent directory av cmd-mappen).

## Kommandoer

### 📦 Backup Kommandoer
- **Hent siste endringer (Pull)** - Henter siste endringer fra remote repository. Sjekker automatisk om du har lokale endringer og tilbyr å stashe dem før pull.
- **Lag safety-tag** - Lager tidsstemplet tag (format: `safety-YYYYMMDD-HHMMSS`) og pusher til remote
- **Lag backup-tag** - Lager tidsstemplet tag (format: `backup-YYYYMMDD-HHMMSS`) og pusher til remote
- **Commit + Push** - Legger til alle endringer, committer og pusher til remote

### ℹ️ Vis Informasjon
- **Vis status** - Viser current branch, siste commit, tags og endringer
- **Vis logg** - Viser de siste 25 commits
- **Vis safety-tags** - Lister opp de siste 10 safety-tags
- **Vis backup-tags** - Lister opp de siste 10 backup-tags

### ⏮️ Gjenopprett Backup
- **Checkout tag** - Sjekker ut en tag (detached HEAD - kan se på koden uten å endre)
- **Tilbakestill til tag** - HARD RESET til en tag (SLETTER alle endringer etter taggen!)

### 🛠️ Diverse
- **Åpne README.md** - Åpner prosjektets README.md i TextEdit
- **Åpne i Xcode** - Åpner .xcworkspace eller .xcodeproj i Xcode

## Gjenopprett fra Backup

For å gjenopprette til en backup:

1. Kjør `gitmenu.command`
2. Velg alternativ 6 eller 7 for å se tilgjengelige tags
3. Velg alternativ 8 for checkout (midlertidig) eller 9 for hard reset (permanent)

### Forskjell mellom Checkout og Hard Reset

- **Checkout tag (8)**: Du kan se koden slik den var på det tidspunktet, men du er i "detached HEAD" state. Bruk `git switch main` for å gå tilbake til hovedbranchen.
- **Hard reset (9)**: ⚠️ PERMANENT! Sletter alle endringer etter taggen. Kan ikke angres.

## Jobbe på en annen maskin (f.eks. MacBook)

Når du skal jobbe på en annen maskin:

1. Hvis prosjektet ikke finnes lokalt ennå:
   ```bash
   cd ~/Swift
   git clone https://github.com/lapstuen/gInfo.git
   ```

2. Hvis prosjektet allerede finnes:
   - Dobbeltklikk `cmd/gitmenu.command`
   - Velg alternativ **1** (Hent siste endringer)
   - Scriptet vil automatisk pull siste endringer fra remote

3. Start å jobbe!

### Hva skjer ved pull med lokale endringer?

Scriptet sjekker automatisk om du har lokale endringer:
- **Hvis du har endringer**: Du får tilbud om å stashe dem før pull
- **Etter pull**: Du får tilbud om å hente tilbake de stashede endringene
- **Hvis ingen endringer**: Pull kjører direkte

## First-time Setup

Første gang du dobbeltklikker på en .command-fil, kan macOS spørre om du er sikker. Klikk "Åpne" for å tillate.
