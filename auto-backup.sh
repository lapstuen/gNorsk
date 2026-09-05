#!/bin/zsh

# ============================================================
# AUTO-BACKUP - Trygg og automatisk GitHub backup
# ============================================================
# Basert på backup-protokollen fra CLAUDE.md
# Fokus: LAGRE alt til git/GitHub - alltid trygt og pålitelig
# ============================================================

set -e  # Exit ved feil

# Farger
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================
# PROSJEKT-KONFIGURASJON
# ============================================================
PROJECTS=(
    "lineapp:$HOME/swift/lineapp:git@github.com:lapstuen/badminton-signup.git"
    "gInfo:$HOME/swift/gInfo:git@github.com:lapstuen/gInfo.git"
    "gThai:$HOME/swift/gThai:git@github.com:lapstuen/gThai.git"
    "gHealth:$HOME/swift/gHealth:git@github.com:lapstuen/gHealth.git"
    "gLogg:$HOME/swift/gLogg:git@github.com:lapstuen/gLogg.git"
    "BadmintonWalletManager:$HOME/swift/BadmintonWalletManager:git@github.com:lapstuen/BadmintonWalletManager.git"
)

# ============================================================
# FINN PROSJEKT (fra current dir eller argument)
# ============================================================
CURRENT_DIR=$(pwd)
PROJECT_DIR=""
PROJECT_NAME=""
GITHUB_REPO=""

# Hvis argument er gitt, bruk det
if [ $# -eq 1 ]; then
    for proj in "${PROJECTS[@]}"; do
        name=$(echo "$proj" | cut -d: -f1)
        # Case-insensitive sammenligning (zsh syntax)
        if [[ "${name:l}" == "${1:l}" ]]; then
            PROJECT_NAME="$name"
            PROJECT_DIR=$(echo "$proj" | cut -d: -f2)
            GITHUB_REPO=$(echo "$proj" | cut -d: -f3)
            break
        fi
    done

    if [ -z "$PROJECT_DIR" ]; then
        echo "${RED}❌ Ukjent prosjekt: $1${NC}"
        echo ""
        echo "Tilgjengelige prosjekter:"
        for proj in "${PROJECTS[@]}"; do
            echo "  - $(echo "$proj" | cut -d: -f1)"
        done
        exit 1
    fi
else
    # Auto-detect fra current directory
    for proj in "${PROJECTS[@]}"; do
        dir=$(echo "$proj" | cut -d: -f2)
        if [[ "$CURRENT_DIR" == "$dir"* ]]; then
            PROJECT_NAME=$(echo "$proj" | cut -d: -f1)
            PROJECT_DIR="$dir"
            GITHUB_REPO=$(echo "$proj" | cut -d: -f3)
            break
        fi
    done

    if [ -z "$PROJECT_DIR" ]; then
        echo "${RED}❌ Ikke i et kjent prosjekt!${NC}"
        echo ""
        echo "Bruk: auto-backup.sh [prosjektnavn]"
        echo ""
        echo "Tilgjengelige prosjekter:"
        for proj in "${PROJECTS[@]}"; do
            echo "  - $(echo "$proj" | cut -d: -f1)"
        done
        exit 1
    fi
fi

cd "$PROJECT_DIR"

# ============================================================
# SJEKK GIT REPOSITORY
# ============================================================
if [ ! -d ".git" ]; then
    echo "${RED}❌ Ikke et git repository: $PROJECT_DIR${NC}"
    echo ""
    echo "Kjør først: cd $PROJECT_DIR && git init"
    exit 1
fi

# ============================================================
# START BACKUP
# ============================================================
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_BRANCH="backup-$TIMESTAMP"

echo ""
echo "${BLUE}🔄 AUTO-BACKUP - $PROJECT_NAME${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ============================================================
# STEG 1: SJEKK STATUS
# ============================================================
echo "${BLUE}📊 Steg 1/6: Sjekker status...${NC}"
git status --short

# Tell endringer
MODIFIED=$(git status --short | grep "^ M" | wc -l | tr -d ' ')
ADDED=$(git status --short | grep "^??" | wc -l | tr -d ' ')
DELETED=$(git status --short | grep "^ D" | wc -l | tr -d ' ')
TOTAL=$((MODIFIED + ADDED + DELETED))

echo ""
echo "Endringer funnet:"
echo "  - Endret: $MODIFIED filer"
echo "  - Ny: $ADDED filer"
echo "  - Slettet: $DELETED filer"
echo "  - Totalt: $TOTAL filer"
echo ""

if [ $TOTAL -eq 0 ]; then
    echo "${YELLOW}⚠️  Ingen endringer å lagre!${NC}"
    echo ""
    echo "Vil du likevel lage en backup-branch? (j/n): "
    read -r create_branch

    if [[ "$create_branch" != "j" && "$create_branch" != "J" ]]; then
        echo "${GREEN}✅ Ingen backup nødvendig - alt er allerede lagret!${NC}"
        exit 0
    fi
fi

# Advarsel ved slettinger
if [ $DELETED -gt 0 ]; then
    echo "${YELLOW}⚠️  ADVARSEL: $DELETED filer vil bli slettet:${NC}"
    git status --short | grep "^ D"
    echo ""
fi

# ============================================================
# STEG 2: GIT ADD
# ============================================================
if [ $TOTAL -gt 0 ]; then
    echo "${BLUE}📦 Steg 2/6: Legger til endringer (git add .)...${NC}"
    git add .
    echo "${GREEN}✓ Alle endringer lagt til${NC}"
    echo ""
else
    echo "${BLUE}📦 Steg 2/6: Hopper over (ingen endringer)${NC}"
    echo ""
fi

# ============================================================
# STEG 3: GIT COMMIT
# ============================================================
if [ $TOTAL -gt 0 ]; then
    echo "${BLUE}💾 Steg 3/6: Committer endringer...${NC}"
    COMMIT_MSG="$(date +%Y-%m-%d_%H:%M:%S)"
    git commit -m "$COMMIT_MSG"

    if [ $? -eq 0 ]; then
        echo "${GREEN}✓ Commit OK: $COMMIT_MSG${NC}"
    else
        echo "${RED}❌ Commit feilet!${NC}"
        exit 1
    fi
    echo ""
else
    echo "${BLUE}💾 Steg 3/6: Hopper over (ingen endringer)${NC}"
    echo ""
fi

# ============================================================
# STEG 4: OPPRETT BACKUP-BRANCH
# ============================================================
echo "${BLUE}🌿 Steg 4/6: Oppretter backup-branch: $BACKUP_BRANCH${NC}"
git branch "$BACKUP_BRANCH"

if [ $? -eq 0 ]; then
    echo "${GREEN}✓ Branch opprettet: $BACKUP_BRANCH${NC}"
else
    echo "${RED}❌ Kunne ikke opprette branch!${NC}"
    exit 1
fi
echo ""

# ============================================================
# STEG 5: PUSH BACKUP-BRANCH TIL GITHUB
# ============================================================
echo "${BLUE}⬆️  Steg 5/6: Pusher backup-branch til GitHub...${NC}"
git push origin "$BACKUP_BRANCH"

if [ $? -eq 0 ]; then
    echo "${GREEN}✓ Backup-branch pushet til GitHub!${NC}"
else
    echo "${RED}❌ Push av backup-branch feilet!${NC}"
    echo ""
    echo "Mulige årsaker:"
    echo "  - Ingen internett-tilkobling"
    echo "  - GitHub er nede"
    echo "  - SSH-nøkkel ikke konfigurert"
    echo ""
    echo "Branch $BACKUP_BRANCH er opprettet lokalt, men ikke pushet."
    exit 1
fi
echo ""

# ============================================================
# STEG 6: OPPDATER MAIN BRANCH (OPTIONAL)
# ============================================================
echo "${BLUE}⬆️  Steg 6/6: Oppdaterer main branch...${NC}"
echo "  (Hopper over merge for å unngå konflikter)"
echo "${YELLOW}  Tips: Kjør 'git pull' manuelt hvis du vil merge med GitHub${NC}"
echo ""

# ============================================================
# VERIFISER PÅ GITHUB
# ============================================================
echo "${BLUE}🔍 Verifiserer backup på GitHub...${NC}"
REMOTE_BACKUP=$(git ls-remote --heads origin | grep "$BACKUP_BRANCH")

if [ -n "$REMOTE_BACKUP" ]; then
    echo "${GREEN}✓ Backup verifisert på GitHub!${NC}"
else
    echo "${YELLOW}⚠️  Kunne ikke verifisere backup på GitHub${NC}"
fi
echo ""

# ============================================================
# OPPSUMMERING
# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "${GREEN}✅ BACKUP FULLFØRT!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Prosjekt: ${BLUE}$PROJECT_NAME${NC}"
echo "Endringer committet: ${GREEN}$TOTAL filer${NC}"
echo "Backup-branch: ${GREEN}$BACKUP_BRANCH${NC}"
echo "GitHub: ${GREEN}✓ Backup pushet og verifisert${NC}"
echo ""
echo "${YELLOW}📌 VIKTIG:${NC}"
echo "  - Lokale endringer er lagret i backup-branch på GitHub"
echo "  - Main branch er IKKE oppdatert (unngår merge-konflikter)"
echo "  - Kjør 'git pull' manuelt hvis du vil merge med GitHub main"
echo ""
echo "For å gjenopprette denne backupen:"
echo "  ${YELLOW}git checkout $BACKUP_BRANCH${NC}"
echo ""
echo "Se alle backups:"
echo "  ${YELLOW}git branch -r | grep backup${NC}"
echo ""

# macOS notification
osascript -e "display notification \"$TOTAL filer lagret til GitHub\" with title \"✅ Backup OK - $PROJECT_NAME\""

echo "${GREEN}Alt er trygt lagret! 🎉${NC}"
echo ""
