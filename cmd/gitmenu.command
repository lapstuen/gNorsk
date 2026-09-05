#!/bin/bash
# gitmenu – Git-kommandoer for macOS Terminal
# Dobbeltklikk i Finder for å kjøre
# Jobber automatisk i prosjektmappen (parent directory)

set -euo pipefail

# Gå til prosjektmappen (opp fra cmd-folder)
cd "$(dirname "$0")/.."
PROSJEKT_NAVN="${PWD##*/}"

# Sjekk at vi står i et Git-repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ Dette er ikke et Git-repo. Gå til prosjektroten og prøv igjen."
  read -p "Trykk Enter for å avslutte..."
  exit 1
fi

clear
echo "════════════════════════════════════════"
echo "   🧭  Git Menu - $PROSJEKT_NAVN"
echo "════════════════════════════════════════"
echo ""
echo "📦 BACKUP KOMMANDOER"
echo "  1. Hent siste endringer (Pull fra remote)"
echo "  2. Lag safety-tag (tidsstemplet) + Push"
echo "  3. Lag backup-tag (tidsstemplet) + Push"
echo "  4. Commit + Push alle endringer"
echo ""
echo "ℹ️  VIS INFORMASJON"
echo "  5. Vis status (branch, siste commit, tags)"
echo "  6. Vis logg (siste 25 commits)"
echo "  7. Vis alle safety-tags (siste 10)"
echo "  8. Vis alle backup-tags (siste 10)"
echo ""
echo "⏮️  GJENOPPRETT BACKUP"
echo "  9. Checkout tag (DETACHED HEAD)"
echo " 10. Tilbakestill til tag (HARD RESET)"
echo ""
echo "🛠️  DIVERSE"
echo " 11. Åpne README.md i TextEdit"
echo " 12. Åpne i Xcode"
echo " 13. Avslutt"
echo "════════════════════════════════════════"
read -p "Velg et tall: " valg
echo ""

case "$valg" in
  1)
    # Pull fra remote
    echo "⤵️  Henter siste endringer fra remote..."
    echo "📌 Current branch: $(git rev-parse --abbrev-ref HEAD)"

    # Sjekk om det er lokale endringer
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
      echo "⚠️  Du har lokale endringer som ikke er committet:"
      git status --short
      echo ""
      read -p "Vil du stashe endringene før pull? (j/n): " stash_choice
      if [ "$stash_choice" == "j" ] || [ "$stash_choice" == "J" ]; then
        git stash save "Auto-stash før pull $(date '+%Y-%m-%d %H:%M:%S')"
        echo "📦 Endringer stashet."
      fi
    fi

    git pull || { echo "❌ Pull feilet. Sjekk konflikter eller nettverk."; exit 1; }
    echo "✅ Pull fullført!"

    # Hvis vi stashet, spør om vi skal poppe
    if git stash list | grep -q "Auto-stash før pull"; then
      echo ""
      read -p "Vil du hente tilbake stashede endringer? (j/n): " pop_choice
      if [ "$pop_choice" == "j" ] || [ "$pop_choice" == "J" ]; then
        git stash pop
        echo "✅ Stashede endringer hentet tilbake."
      fi
    fi
    ;;

  2)
    # Safety-tag (brukes av Claude før endringer)
    read -p "Tag-melding (valgfri): " tmsg
    tagname="safety-$(date +%Y%m%d-%H%M%S)"
    if [ -z "$tmsg" ]; then
      git tag -a "$tagname" -m "Safety backup created $(date '+%Y-%m-%d %H:%M:%S')"
    else
      git tag -a "$tagname" -m "$tmsg"
    fi
    echo "🏷️  Opprettet tag: $tagname"
    echo "⤴️  Pusher tag til origin..."
    git push origin "$tagname" || { echo "❌ Push feilet."; exit 1; }
    echo "✅ Safety-tag opprettet og pushet!"
    ;;

  3)
    # Backup-tag (generell backup)
    read -p "Tag-melding: " tmsg
    tagname="backup-$(date +%Y%m%d-%H%M%S)"
    git tag -a "$tagname" -m "$tmsg"
    echo "🏷️  Opprettet tag: $tagname"
    echo "⤴️  Pusher tag til origin..."
    git push origin "$tagname" || { echo "❌ Push feilet."; exit 1; }
    echo "✅ Backup-tag opprettet og pushet!"
    ;;

  4)
    # Commit + Push
    read -p "Commit-melding: " msg
    git add -A
    git commit -m "$msg" || echo "ℹ️ Ingen endringer å committe."
    echo "⤴️  Pusher til origin..."
    git push || { echo "❌ Push feilet. Sjekk divergens eller remote."; exit 1; }
    echo "✅ Commit og push fullført!"
    ;;

  5)
    # Vis status
    echo "📌 Branch: $(git rev-parse --abbrev-ref HEAD)"
    echo "📝 Siste commit: $(git log -1 --pretty=format:'%h %s (%cr)')"
    echo ""
    echo "🏷️  Alle tags (siste 10):"
    git tag --sort=-creatordate | head -n 10
    echo ""
    echo "📊 Endringer:"
    git status --short
    ;;

  6)
    # Vis logg
    echo "📜 Git log (siste 25 commits):"
    git log --oneline --pretty=format:"%C(yellow)%h%Creset %ad %s" --date=short | head -n 25
    ;;

  7)
    # Vis safety-tags
    echo "🏷️  Safety-tags (siste 10):"
    git tag -l "safety-*" --sort=-creatordate | head -n 10
    ;;

  8)
    # Vis backup-tags
    echo "🏷️  Backup-tags (siste 10):"
    git tag -l "backup-*" --sort=-creatordate | head -n 10
    ;;

  9)
    # Checkout tag (detached HEAD)
    echo "🏷️  Tilgjengelige tags:"
    git tag --sort=-creatordate | head -n 20
    echo ""
    read -p "Skriv tag-navn å sjekke ut (DETACHED HEAD): " t
    if git rev-parse -q --verify "refs/tags/$t" >/dev/null; then
      echo "⚠️  Du går i detached HEAD. For å gå tilbake: 'git switch main' eller 'git switch -'"
      git checkout "$t"
      echo "✅ Sjekket ut tag: $t"
    else
      echo "❌ Fant ikke tag: $t"
      exit 1
    fi
    ;;

  10)
    # Hard reset til tag
    echo "⚠️  ADVARSEL: Dette vil SLETTE alle endringer etter taggen!"
    echo "🏷️  Tilgjengelige tags:"
    git tag --sort=-creatordate | head -n 20
    echo ""
    read -p "Skriv tag-navn å tilbakestille til: " t
    if git rev-parse -q --verify "refs/tags/$t" >/dev/null; then
      read -p "Er du SIKKER? Dette kan ikke angres! (skriv JA): " confirm
      if [ "$confirm" == "JA" ]; then
        git reset --hard "$t"
        echo "✅ Tilbakestilt til tag: $t"
      else
        echo "❌ Avbrutt."
      fi
    else
      echo "❌ Fant ikke tag: $t"
      exit 1
    fi
    ;;

  11)
    # Åpne README.md i TextEdit
    [ -f README.md ] || echo "# $PROSJEKT_NAVN" > README.md
    open -e README.md
    echo "✅ Åpnet README.md i TextEdit"
    ;;

  12)
    # Åpne i Xcode
    proj=$(ls -1 *.xcworkspace *.xcodeproj 2>/dev/null | head -n 1 || true)
    if [ -n "${proj:-}" ]; then
      open "$proj"
      echo "✅ Åpnet $proj i Xcode"
    else
      echo "ℹ️ Fant ikke .xcodeproj/.xcworkspace. Åpner Finder..."
      open .
    fi
    ;;

  13)
    # Avslutt
    echo "👋 Avslutter..."
    exit 0
    ;;

  *)
    echo "❌ Ugyldig valg."
    exit 1
    ;;
esac

echo ""
read -p "Trykk Enter for å lukke..."
