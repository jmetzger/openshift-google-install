#!/bin/bash

# OpenShift 4 on Google Cloud Installation Script
# Based on Red Hat Training Video Transcript
# Interactive installation guide with step-by-step instructions

# set -e  # Disabled to allow graceful error handling

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
LOG_FILE="openshift-install.log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_step() {
    echo -e "${GREEN}>>> $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

wait_for_user() {
    echo -e "${YELLOW}$1${NC}"
    echo -e "${YELLOW}Drücken Sie Enter, um fortzufahren...${NC}"
    read -r
}

# Deutschland-spezifische Standardwerte
DEFAULT_GCP_REGION="europe-west3"  # Frankfurt
DEFAULT_GCP_ZONE="europe-west3-c"
DEFAULT_GCP_PROJECT="ocp4-germany-$(date +%Y%m%d)"
DEFAULT_GCP_SA="osd-ccs-admin"

# Automatische Tool-Installation Funktionen
detect_architecture() {
    local arch=$(uname -m)
    case $arch in
        x86_64) echo "x86_64" ;;
        aarch64|arm64) echo "arm" ;;
        *) echo "x86_64" ;; # Default fallback
    esac
}

check_sudo_access() {
    if ! sudo -n true 2>/dev/null; then
        print_warning "Sudo-Berechtigung erforderlich für automatische Tool-Installation"
        if ! sudo true; then
            print_error "Sudo-Zugriff verweigert. Manuelle Installation erforderlich."
            return 1
        fi
    fi
    return 0
}

install_gcloud_cli() {
    print_step "Installiere Google Cloud CLI automatisch..."
    
    local arch=$(detect_architecture)
    local download_url
    local temp_dir=$(mktemp -d)
    
    if [[ "$arch" == "arm" ]]; then
        download_url="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-arm.tar.gz"
    else
        download_url="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz"
    fi
    
    print_step "Lade Google Cloud CLI herunter von: $download_url"
    cd "$temp_dir"
    
    if command -v curl &> /dev/null; then
        curl -L -o google-cloud-cli.tar.gz "$download_url"
    elif command -v wget &> /dev/null; then
        wget -O google-cloud-cli.tar.gz "$download_url"
    else
        print_error "Weder curl noch wget verfügbar. Bitte installieren Sie eines dieser Tools."
        return 1
    fi
    
    print_step "Extrahiere und installiere Google Cloud CLI..."
    tar -xzf google-cloud-cli.tar.gz
    
    # Installiere in /opt und erstelle Symlinks
    sudo mkdir -p /opt
    sudo rm -rf /opt/google-cloud-sdk
    sudo mv google-cloud-sdk /opt/
    
    # Erstelle Symlinks in /usr/local/bin
    sudo ln -sf /opt/google-cloud-sdk/bin/gcloud /usr/local/bin/gcloud
    sudo ln -sf /opt/google-cloud-sdk/bin/gsutil /usr/local/bin/gsutil
    sudo ln -sf /opt/google-cloud-sdk/bin/bq /usr/local/bin/bq
    
    # Non-interaktive Installation
    /opt/google-cloud-sdk/install.sh --quiet --usage-reporting=false --path-update=false
    
    # Cleanup
    cd - &>/dev/null
    rm -rf "$temp_dir"
    
    print_step "Google Cloud CLI erfolgreich installiert ✓"
    gcloud --version
    return 0
}

install_openshift_tools() {
    print_step "Installiere OpenShift CLI Tools automatisch..."
    
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Installiere oc CLI
    print_step "Lade OpenShift oc CLI herunter..."
    if command -v curl &> /dev/null; then
        curl -L -o openshift-client-linux.tar.gz "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz"
    else
        wget -O openshift-client-linux.tar.gz "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz"
    fi
    
    tar -xzf openshift-client-linux.tar.gz
    sudo mv oc /usr/local/bin/
    sudo mv kubectl /usr/local/bin/
    sudo chmod +x /usr/local/bin/oc /usr/local/bin/kubectl
    
    # Installiere openshift-install
    print_step "Lade OpenShift Installer herunter..."
    if command -v curl &> /dev/null; then
        curl -L -o openshift-install-linux.tar.gz "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-install-linux.tar.gz"
    else
        wget -O openshift-install-linux.tar.gz "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-install-linux.tar.gz"
    fi
    
    tar -xzf openshift-install-linux.tar.gz
    sudo mv openshift-install /usr/local/bin/
    sudo chmod +x /usr/local/bin/openshift-install
    
    # Cleanup
    cd - &>/dev/null
    rm -rf "$temp_dir"
    
    print_step "OpenShift CLI Tools erfolgreich installiert ✓"
    oc version --client
    openshift-install version
    return 0
}

install_dig_command() {
    print_step "Installiere dig (DNS lookup tool) automatisch..."
    
    # Erkenne das Betriebssystem
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        local os_id="$ID"
    else
        print_error "Kann Betriebssystem nicht erkennen"
        return 1
    fi
    
    case "$os_id" in
        ubuntu|debian)
            print_step "Installiere dnsutils für Ubuntu/Debian..."
            sudo apt-get update -qq
            sudo apt-get install -y dnsutils
            ;;
        centos|rhel|fedora|rocky|almalinux)
            print_step "Installiere bind-utils für RHEL/CentOS/Fedora..."
            if command -v dnf &> /dev/null; then
                sudo dnf install -y bind-utils
            else
                sudo yum install -y bind-utils
            fi
            ;;
        opensuse*|sles)
            print_step "Installiere bind-utils für openSUSE/SLES..."
            sudo zypper install -y bind-utils
            ;;
        arch)
            print_step "Installiere bind für Arch Linux..."
            sudo pacman -S --noconfirm bind
            ;;
        *)
            print_warning "Unbekanntes Betriebssystem: $os_id"
            print_step "Versuche generische Installation..."
            if command -v apt-get &> /dev/null; then
                sudo apt-get update -qq && sudo apt-get install -y dnsutils
            elif command -v yum &> /dev/null; then
                sudo yum install -y bind-utils
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y bind-utils
            else
                print_error "Keine unterstützte Paketverwaltung gefunden"
                return 1
            fi
            ;;
    esac
    
    # Verifiziere Installation
    if command -v dig &> /dev/null; then
        print_step "dig erfolgreich installiert ✓"
        dig -v
        return 0
    else
        print_error "dig Installation fehlgeschlagen"
        return 1
    fi
}

auto_install_missing_tools() {
    print_header "Automatische Tool-Installation"
    
    # Prüfe sudo-Zugriff
    if ! check_sudo_access; then
        return 1
    fi
    
    local tools_to_install=()
    
    # Prüfe welche Tools fehlen
    if ! command -v gcloud &> /dev/null; then
        tools_to_install+=("gcloud")
    fi
    
    if ! command -v oc &> /dev/null; then
        tools_to_install+=("oc")
    fi
    
    if ! command -v openshift-install &> /dev/null; then
        tools_to_install+=("openshift-install")
    fi
    
    if ! command -v dig &> /dev/null; then
        tools_to_install+=("dig")
    fi
    
    if [ ${#tools_to_install[@]} -eq 0 ]; then
        print_step "Alle erforderlichen Tools sind bereits installiert ✓"
        return 0
    fi
    
    print_step "Fehlende Tools gefunden: ${tools_to_install[*]}"
    echo ""
    echo "HINWEIS: Geben Sie 'j' ein, um die automatische Installation zu starten!"
    read -p "Sollen die fehlenden Tools automatisch installiert werden? (j/N): " auto_install
    
    if [[ ! "$auto_install" =~ ^[jJyY] ]]; then
        print_warning "Automatische Installation übersprungen"
        return 1
    fi
    
    # Installiere gcloud falls erforderlich
    if [[ " ${tools_to_install[*]} " =~ " gcloud " ]]; then
        if ! install_gcloud_cli; then
            print_error "Google Cloud CLI Installation fehlgeschlagen"
            return 1
        fi
    fi
    
    # Installiere OpenShift Tools falls erforderlich
    if [[ " ${tools_to_install[*]} " =~ " oc " ]] || [[ " ${tools_to_install[*]} " =~ " openshift-install " ]]; then
        if ! install_openshift_tools; then
            print_error "OpenShift Tools Installation fehlgeschlagen"
            return 1
        fi
    fi
    
    # Installiere dig falls erforderlich
    if [[ " ${tools_to_install[*]} " =~ " dig " ]]; then
        if ! install_dig_command; then
            print_error "dig Installation fehlgeschlagen"
            return 1
        fi
    fi
    
    print_step "Alle Tools erfolgreich installiert! ✓"
    return 0
}

load_config_file() {
    local config_file=".openshift-install-config"
    
    if [ -f "$config_file" ]; then
        print_step "Lade Konfiguration aus $config_file..."
        source "$config_file"
        print_step "Konfiguration geladen ✓"
        return 0
    fi
    return 1
}

save_config_file() {
    local config_file=".openshift-install-config"
    
    print_step "Speichere Konfiguration in $config_file..."
    cat > "$config_file" << EOF
# OpenShift auf Google Cloud Konfiguration
# Generiert am $(date)
GCP_PROJECT="$GCP_PROJECT"
GCP_SA="$GCP_SA"
GCP_DOMAIN="$GCP_DOMAIN"
GCP_REGION="$GCP_REGION"
GCP_ZONE="$GCP_ZONE"
BILLING_ACCOUNT_ID="$BILLING_ACCOUNT_ID"
SERVICE_ACCOUNT_JSON="${SERVICE_ACCOUNT_JSON:-}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
EOF
    
    print_step "Konfiguration gespeichert ✓"
}

# Erweiterte Automatisierungsfunktionen
auto_detect_billing_account() {
    print_step "Suche verfügbare Billing Accounts..."
    
    local billing_accounts
    billing_accounts=$(gcloud alpha billing accounts list --format="value(name)" 2>/dev/null)
    
    if [ -z "$billing_accounts" ]; then
        print_warning "Keine Billing Accounts gefunden"
        return 1
    fi
    
    local account_count
    account_count=$(echo "$billing_accounts" | wc -l)
    
    if [ "$account_count" -eq 1 ]; then
        BILLING_ACCOUNT_ID=$(echo "$billing_accounts" | head -1 | sed 's/.*\///')
        print_step "Automatisch erkannter Billing Account: $BILLING_ACCOUNT_ID"
        return 0
    else
        print_warning "Mehrere Billing Accounts gefunden ($account_count). Manuelle Auswahl erforderlich."
        return 1
    fi
}

monitor_dns_propagation() {
    local domain="$1"
    local max_attempts=30
    local attempt=1
    
    print_step "Überwache DNS Propagation für $domain..."
    
    while [ $attempt -le $max_attempts ]; do
        print_step "Versuch $attempt/$max_attempts: Prüfe DNS Propagation..."
        
        if dig NS "$domain" +short | grep -q "ns-cloud"; then
            print_step "DNS Propagation erfolgreich nach $attempt Versuchen ✓"
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            print_step "Warte 30 Sekunden für nächsten Versuch..."
            sleep 30
        fi
        
        ((attempt++))
    done
    
    print_warning "DNS Propagation noch nicht vollständig nach $max_attempts Versuchen"
    return 1
}

auto_detect_ssh_key() {
    print_step "Suche nach vorhandenen SSH Keys..."
    
    local ssh_dir="$HOME/.ssh"
    local default_keys=("id_rsa" "id_ed25519" "id_ecdsa")
    
    for key in "${default_keys[@]}"; do
        if [ -f "$ssh_dir/$key" ] && [ -f "$ssh_dir/$key.pub" ]; then
            print_step "SSH Key gefunden: $ssh_dir/$key ✓"
            SSH_KEY_PATH="$ssh_dir/$key.pub"
            return 0
        fi
    done
    
    print_warning "Kein SSH Key gefunden. Generiere neuen SSH Key..."
    return 1
}

generate_ssh_key() {
    local ssh_dir="$HOME/.ssh"
    local key_path="$ssh_dir/openshift_rsa"
    
    print_step "Generiere neuen SSH Key für OpenShift..."
    
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    
    ssh-keygen -t rsa -b 4096 -f "$key_path" -N "" -C "openshift@$(hostname)"
    
    if [ $? -eq 0 ]; then
        print_step "SSH Key erfolgreich generiert: $key_path ✓"
        SSH_KEY_PATH="$key_path.pub"
        return 0
    else
        print_error "SSH Key Generierung fehlgeschlagen"
        return 1
    fi
}

check_quotas_automatically() {
    print_step "Prüfe aktuelle Quotas automatisch..."
    
    local cpu_quota
    local disk_quota
    local region_cpu_quota
    local region_disk_quota
    
    # Prüfe verschiedene CPU Quota Namen
    cpu_quota=$(gcloud compute project-info describe --format="value(quotas[name:CPUS].limit)" 2>/dev/null)
    region_cpu_quota=$(gcloud compute regions describe "$GCP_REGION" --format="value(quotas[name:CPUS].limit)" 2>/dev/null)
    
    # Prüfe verschiedene Disk Quota Namen  
    disk_quota=$(gcloud compute project-info describe --format="value(quotas[name:SSD_TOTAL_GB].limit)" 2>/dev/null)
    if [ -z "$disk_quota" ]; then
        disk_quota=$(gcloud compute project-info describe --format="value(quotas[name:LOCAL_SSD_TOTAL_GB].limit)" 2>/dev/null)
    fi
    region_disk_quota=$(gcloud compute regions describe "$GCP_REGION" --format="value(quotas[name:SSD_TOTAL_GB].limit)" 2>/dev/null)
    
    # Verwende regionale Quotas falls verfügbar
    if [ -n "$region_cpu_quota" ]; then
        cpu_quota="$region_cpu_quota"
    fi
    if [ -n "$region_disk_quota" ]; then
        disk_quota="$region_disk_quota"
    fi
    
    print_step "Aktuelle Quotas für Region $GCP_REGION:"
    echo "  CPUs: ${cpu_quota:-Unbekannt}"
    echo "  SSD Storage: ${disk_quota:-Unbekannt} GB"
    
    # Falls Quotas immer noch unbekannt, versuche alternative Methode
    if [ -z "$cpu_quota" ] || [ -z "$disk_quota" ]; then
        print_step "Versuche alternative Quota-Abfrage..."
        
        # Liste alle Quotas und filtere
        local all_quotas
        all_quotas=$(gcloud compute project-info describe --format="table(quotas.metric,quotas.limit,quotas.usage)" 2>/dev/null | grep -E "(CPU|SSD)")
        
        if [ -n "$all_quotas" ]; then
            echo ""
            echo "Verfügbare Quota-Informationen:"
            echo "$all_quotas"
            echo ""
        fi
        
        # Extrahiere CPU Quota aus der Tabelle
        if [ -z "$cpu_quota" ]; then
            cpu_quota=$(echo "$all_quotas" | grep -i "cpus" | head -1 | awk '{print $2}' 2>/dev/null)
        fi
        
        # Extrahiere SSD Quota aus der Tabelle
        if [ -z "$disk_quota" ]; then
            disk_quota=$(echo "$all_quotas" | grep -i "ssd" | head -1 | awk '{print $2}' 2>/dev/null)
        fi
        
        print_step "Nach alternativer Abfrage:"
        echo "  CPUs: ${cpu_quota:-Unbekannt}"
        echo "  SSD Storage: ${disk_quota:-Unbekannt} GB"
    fi
    
    # Prüfe ob Quotas ausreichend sind
    local quota_sufficient=true
    
    if [ -n "$cpu_quota" ] && [ "$cpu_quota" != "Unbekannt" ] && [ "$cpu_quota" -ge 40 ] 2>/dev/null; then
        print_step "CPU Quota ist ausreichend (${cpu_quota} >= 40) ✓"
    else
        print_warning "CPU Quota möglicherweise unzureichend (${cpu_quota:-?} < 40)"
        quota_sufficient=false
    fi
    
    if [ -n "$disk_quota" ] && [ "$disk_quota" != "Unbekannt" ] && [ "$disk_quota" -ge 950 ] 2>/dev/null; then
        print_step "Disk Quota ist ausreichend (${disk_quota} >= 950) ✓"
    else
        print_warning "Disk Quota möglicherweise unzureichend (${disk_quota:-?} < 950)"
        quota_sufficient=false
    fi
    
    # Falls Quotas nicht ermittelt werden können, informiere den Benutzer
    if [ -z "$cpu_quota" ] || [ -z "$disk_quota" ] || [ "$cpu_quota" = "Unbekannt" ] || [ "$disk_quota" = "Unbekannt" ]; then
        echo ""
        print_warning "Quota-Informationen konnten nicht vollständig ermittelt werden."
        echo "Bitte prüfen Sie die Quotas manuell in der Google Cloud Console:"
        echo "https://console.cloud.google.com/iam-admin/quotas?project=$GCP_PROJECT"
        echo ""
        echo "Erforderliche Mindestquotas für OpenShift:"
        echo "- Compute Engine API CPUs (Region $GCP_REGION): 40"
        echo "- Compute Engine API Persistent Disk SSD (GB) (Region $GCP_REGION): 950"
        return 1
    fi
    
    if [ "$quota_sufficient" = "true" ]; then
        return 0
    else
        return 1
    fi
}

retry_with_backoff() {
    local max_attempts=3
    local delay=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        print_step "Versuch $attempt/$max_attempts: $*"
        
        if "$@"; then
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            print_warning "Fehlgeschlagen. Wiederholung in $delay Sekunden..."
            sleep $delay
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        ((attempt++))
    done
    
    print_error "Alle Versuche fehlgeschlagen für: $*"
    return 1
}

# Erweiterte Service Account Funktionen
list_service_accounts() {
    print_step "Verfügbare Service Accounts:"
    gcloud iam service-accounts list --format="table(email,displayName,disabled)" 2>/dev/null || {
        print_warning "Fehler beim Auflisten der Service Accounts"
        return 1
    }
}

check_service_account_exists() {
    local sa_email="$1"
    if gcloud iam service-accounts describe "$sa_email" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

list_service_account_keys() {
    local sa_email="$1"
    print_step "Verfügbare Schlüssel für $sa_email:"
    gcloud iam service-accounts keys list --iam-account="$sa_email" --format="table(name.basename(),createdTime,keyType)" 2>/dev/null || {
        print_warning "Fehler beim Auflisten der Service Account Schlüssel"
        return 1
    }
}

validate_service_account_json() {
    local json_file="$1"
    
    if [ ! -f "$json_file" ]; then
        print_error "JSON Datei nicht gefunden: $json_file"
        return 1
    fi
    
    # Prüfe JSON Format
    if ! python3 -m json.tool "$json_file" >/dev/null 2>&1 && ! jq . "$json_file" >/dev/null 2>&1; then
        print_error "Ungültiges JSON Format in $json_file"
        return 1
    fi
    
    # Prüfe erforderliche Felder
    local required_fields=("type" "project_id" "private_key_id" "private_key" "client_email")
    for field in "${required_fields[@]}"; do
        if ! grep -q "\"$field\"" "$json_file"; then
            print_error "Erforderliches Feld fehlt in JSON: $field"
            return 1
        fi
    done
    
    print_step "Service Account JSON erfolgreich validiert ✓"
    
    # Zeige wichtige Informationen
    local project_id client_email
    if command -v jq &>/dev/null; then
        project_id=$(jq -r '.project_id' "$json_file" 2>/dev/null)
        client_email=$(jq -r '.client_email' "$json_file" 2>/dev/null)
    else
        project_id=$(grep -o '"project_id":"[^"]*"' "$json_file" | cut -d'"' -f4)
        client_email=$(grep -o '"client_email":"[^"]*"' "$json_file" | cut -d'"' -f4)
    fi
    
    echo "  Projekt ID: $project_id"
    echo "  Service Account: $client_email"
    
    return 0
}

create_service_account_key() {
    local sa_email="$1"
    local output_file="$2"
    local backup_existing="${3:-true}"
    
    # Backup existierender Datei falls gewünscht
    if [ "$backup_existing" = "true" ] && [ -f "$output_file" ]; then
        local backup_file="${output_file}.backup.$(date +%Y%m%d-%H%M%S)"
        print_step "Erstelle Backup der existierenden Datei: $backup_file"
        cp "$output_file" "$backup_file"
    fi
    
    print_step "Erstelle neuen Service Account Schlüssel..."
    if gcloud iam service-accounts keys create "$output_file" --iam-account="$sa_email" 2>/dev/null; then
        print_step "Service Account Schlüssel erfolgreich erstellt: $output_file ✓"
        
        # Setze sichere Berechtigungen
        chmod 600 "$output_file"
        
        # Validiere die erstellte Datei
        if validate_service_account_json "$output_file"; then
            return 0
        else
            print_error "Validierung der erstellten JSON Datei fehlgeschlagen"
            return 1
        fi
    else
        print_error "Fehler beim Erstellen des Service Account Schlüssels"
        return 1
    fi
}

interactive_service_account_selection() {
    print_step "Interaktive Service Account Auswahl..."
    
    # Liste verfügbare Service Accounts
    local sa_list
    sa_list=$(gcloud iam service-accounts list --format="value(email)" 2>/dev/null)
    
    if [ -z "$sa_list" ]; then
        print_warning "Keine Service Accounts gefunden"
        return 1
    fi
    
    echo ""
    echo "Verfügbare Service Accounts:"
    local i=1
    local sa_array=()
    while IFS= read -r sa; do
        echo "  $i) $sa"
        sa_array+=("$sa")
        ((i++))
    done <<< "$sa_list"
    
    echo ""
    read -p "Wählen Sie einen Service Account (1-$((i-1))): " selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le $((i-1)) ]; then
        echo "${sa_array[$((selection-1))]}"
        return 0
    else
        print_error "Ungültige Auswahl"
        return 1
    fi
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "$1 ist nicht installiert!"
        return 1
    fi
    print_step "$1 ist verfügbar ✓"
    return 0
}

print_header "OpenShift 4 Installation auf Google Cloud - Deutschland Optimiert"
echo "Dieses Script führt Sie durch die automatisierte Installation von OpenShift 4 auf Google Cloud Platform"
echo "Optimiert für Deutschland mit Frankfurt Region und GDPR-Compliance"
echo "Basierend auf dem Red Hat Training Video"
echo ""

# Lade bestehende Konfiguration falls vorhanden
load_config_file

# Step 1: Automatische Tool-Installation
print_header "Schritt 1: Tool-Installation und Voraussetzungen"

# Versuche automatische Installation fehlender Tools
if ! auto_install_missing_tools; then
    print_warning "Automatische Installation nicht möglich oder übersprungen"
    
    # Fallback zur manuellen Prüfung
    print_step "Prüfe verfügbare Tools..."
    MISSING_TOOLS=()
    
    if ! check_command "gcloud"; then
        MISSING_TOOLS+=("gcloud CLI")
    fi
    
    if ! check_command "oc"; then
        MISSING_TOOLS+=("oc CLI")
    fi
    
    if ! check_command "openshift-install"; then
        MISSING_TOOLS+=("openshift-install")
    fi
    
    if ! check_command "dig"; then
        MISSING_TOOLS+=("dig")
    fi
    
    if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
        print_warning "Fehlende Tools gefunden:"
        for tool in "${MISSING_TOOLS[@]}"; do
            echo "  - $tool"
        done
        echo ""
        echo "Bitte installieren Sie die fehlenden Tools manuell:"
        echo "- gcloud CLI: https://cloud.google.com/sdk/docs/install"
        echo "- oc CLI: https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/"
        echo "- OpenShift Installer: https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/"
        echo "- dig: apt install dnsutils (Ubuntu/Debian) oder yum install bind-utils (RHEL/CentOS)"
        echo ""
        wait_for_user "Installieren Sie die fehlenden Tools und führen Sie das Script erneut aus."
        exit 1
    fi
fi

print_step "Alle erforderlichen Tools sind verfügbar!"

# Prüfe ob openshift-install verfügbar ist
if ! check_command "openshift-install"; then
    print_error "openshift-install ist nicht verfügbar. Automatische Installation fehlgeschlagen."
    exit 1
fi

# Step 2: Manual prerequisites
print_header "Schritt 2: Manuelle Voraussetzungen"
echo "Bevor wir fortfahren, stellen Sie sicher, dass Sie folgende Dinge vorbereitet haben:"
echo ""
echo "🔑 PULL SECRET BESCHAFFEN (ERFORDERLICH):"
echo "Das Pull Secret ist ein spezieller Authentifizierungsschlüssel von Red Hat, der für den"
echo "Download der OpenShift Container Images benötigt wird."
echo ""
echo "📋 Schritt-für-Schritt Anleitung für Pull Secret:"
echo "1. Öffnen Sie https://console.redhat.com/openshift/install/pull-secret"
echo "   (Alternative: https://try.openshift.com)"
echo "2. Falls Sie noch keinen Red Hat Account haben:"
echo "   - Klicken Sie auf 'Register for a Red Hat account'"
echo "   - Registrieren Sie sich kostenlos (keine Kreditkarte erforderlich)"
echo "3. Loggen Sie sich mit Ihrem Red Hat Account ein"
echo "4. Klicken Sie auf 'Copy pull secret' oder 'Download pull secret'"
echo "5. Speichern Sie den Inhalt als 'pull-secret.txt' in diesem Verzeichnis:"
echo "   $(pwd)/pull-secret.txt"
echo ""
echo "💡 WICHTIG: Das Pull Secret ist eine JSON-Datei und muss exakt kopiert werden!"
echo "   Achten Sie darauf, dass keine zusätzlichen Zeichen oder Leerzeichen eingefügt werden."
echo ""
echo "HINWEIS: OpenShift Installer und CLI Tools (oc, kubectl) werden automatisch heruntergeladen!"
echo ""
echo "🔧 Weitere Voraussetzungen:"
echo "6. Stellen Sie sicher, dass Sie:"
echo "   - Zugang zu einem Google Cloud Account haben"
echo "   - Ein Billing Account mit Ihrem GCP Account verknüpft ist"
echo "   - Eine DNS Domain haben (kann über Google gekauft oder delegiert werden)"
echo ""
wait_for_user "Haben Sie alle Voraussetzungen erfüllt?"

# Step 3: Initialize gcloud
print_header "Schritt 3: gcloud CLI initialisieren"
print_step "Initialisiere gcloud CLI..."

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    print_step "Führe gcloud init aus..."
    gcloud init
else
    print_step "gcloud ist bereits initialisiert ✓"
fi

print_step "Verifiziere Verbindung..."
gcloud config list

# Step 4: Set Environment Variables with German Defaults
print_header "Schritt 4: Umgebungsvariablen konfigurieren"

echo "Konfiguration mit Deutschland-optimierten Standardwerten:"
echo "Die Standardregion ist Frankfurt (europe-west3) für GDPR-Compliance"
echo ""

# Verwende geladene Konfiguration oder Standardwerte
if [ -z "$GCP_PROJECT" ]; then
    read -p "Google Cloud Projekt ID [$DEFAULT_GCP_PROJECT]: " GCP_PROJECT
    GCP_PROJECT=${GCP_PROJECT:-$DEFAULT_GCP_PROJECT}
fi

if [ -z "$GCP_SA" ]; then
    echo ""
    echo "Service Account Konfiguration:"
    echo "Der Service Account wird für die OpenShift Installation benötigt."
    echo "Standard: $DEFAULT_GCP_SA"
    echo ""
    read -p "Service Account Name [$DEFAULT_GCP_SA]: " GCP_SA
    GCP_SA=${GCP_SA:-$DEFAULT_GCP_SA}
    
    # Erweiterte Optionen anbieten
    echo ""
    read -p "Erweiterte Service Account Optionen konfigurieren? (j/N): " advanced_sa
    if [[ "$advanced_sa" =~ ^[jJyY] ]]; then
        echo ""
        echo "Erweiterte Optionen:"
        echo "1) Standard Service Account verwenden"
        echo "2) Existierenden Service Account auswählen"
        echo "3) Benutzerdefinierten Service Account Namen eingeben"
        echo ""
        read -p "Wählen Sie eine Option (1-3) [1]: " sa_option
        sa_option=${sa_option:-1}
        
        case $sa_option in
            2)
                echo ""
                print_step "Lade verfügbare Service Accounts..."
                if command -v gcloud &>/dev/null && gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
                    list_service_accounts
                    echo ""
                    read -p "Geben Sie die E-Mail-Adresse des gewünschten Service Accounts ein: " existing_sa_email
                    if [[ "$existing_sa_email" =~ ^[^@]+@[^@]+\.iam\.gserviceaccount\.com$ ]]; then
                        # Extrahiere Service Account Namen aus E-Mail
                        GCP_SA=$(echo "$existing_sa_email" | cut -d'@' -f1)
                        print_step "Service Account Name aus E-Mail extrahiert: $GCP_SA"
                    else
                        print_warning "Ungültige Service Account E-Mail. Verwende Standard: $DEFAULT_GCP_SA"
                        GCP_SA="$DEFAULT_GCP_SA"
                    fi
                else
                    print_warning "gcloud nicht verfügbar oder nicht angemeldet. Verwende Standard."
                fi
                ;;
            3)
                echo ""
                read -p "Geben Sie den benutzerdefinierten Service Account Namen ein: " custom_sa_name
                if [[ -n "$custom_sa_name" && "$custom_sa_name" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]]; then
                    GCP_SA="$custom_sa_name"
                    print_step "Benutzerdefinierter Service Account Name: $GCP_SA"
                else
                    print_warning "Ungültiger Service Account Name. Verwende Standard: $DEFAULT_GCP_SA"
                    GCP_SA="$DEFAULT_GCP_SA"
                fi
                ;;
        esac
    fi
fi

if [ -z "$GCP_DOMAIN" ]; then
    read -p "DNS Domain (z.B. openshift.ihredomain.com): " GCP_DOMAIN
fi

if [ -z "$GCP_REGION" ]; then
    read -p "Region [$DEFAULT_GCP_REGION]: " GCP_REGION
    GCP_REGION=${GCP_REGION:-$DEFAULT_GCP_REGION}
fi

if [ -z "$GCP_ZONE" ]; then
    read -p "Zone [$DEFAULT_GCP_ZONE]: " GCP_ZONE
    GCP_ZONE=${GCP_ZONE:-$DEFAULT_GCP_ZONE}
fi

export GCP_PROJECT="$GCP_PROJECT"
export GCP_SA="$GCP_SA"
export GCP_DOMAIN="$GCP_DOMAIN"
export GCP_REGION="$GCP_REGION"
export GCP_ZONE="$GCP_ZONE"

echo ""
print_step "Umgebungsvariablen gesetzt:"
echo "  Projekt: $GCP_PROJECT"
echo "  Service Account: $GCP_SA"
echo "  Domain: $GCP_DOMAIN"
echo "  Region: $GCP_REGION (Frankfurt)"
echo "  Zone: $GCP_ZONE"

# Speichere Konfiguration für nächste Ausführung
save_config_file

# Step 5: Create Project
print_header "Schritt 5: Google Cloud Projekt erstellen"
print_step "Erstelle Projekt: $GCP_PROJECT"

if gcloud projects describe "$GCP_PROJECT" &>/dev/null; then
    print_warning "Projekt $GCP_PROJECT existiert bereits"
else
    gcloud projects create "$GCP_PROJECT"
    print_step "Projekt $GCP_PROJECT erstellt ✓"
fi

print_step "Setze Projekt als Standard..."
gcloud config set project "$GCP_PROJECT"
gcloud config set compute/region "$GCP_REGION"
gcloud config set compute/zone "$GCP_ZONE"

print_step "Verifiziere Projektkonfiguration..."
gcloud config list

# Step 6: Enable APIs
print_header "Schritt 6: Erforderliche APIs aktivieren"
print_step "Aktiviere erforderliche APIs..."

APIS=(
    "compute.googleapis.com"
    "cloudapis.googleapis.com"
    "cloudresourcemanager.googleapis.com"
    "dns.googleapis.com"
    "iam.googleapis.com"
    "iamcredentials.googleapis.com"
    "servicemanagement.googleapis.com"
    "serviceusage.googleapis.com"
    "storage-api.googleapis.com"
    "cloudbilling.googleapis.com"
    "deploymentmanager.googleapis.com"
    "networksecurity.googleapis.com"
    "orgpolicy.googleapis.com"
)

for api in "${APIS[@]}"; do
    print_step "Aktiviere $api..."
    gcloud services enable "$api"
done

print_step "Alle APIs wurden aktiviert ✓"

# Step 7: Link Billing Account with Auto-Detection
print_header "Schritt 7: Billing Account verknüpfen"

# Verwende gespeicherte Billing Account ID falls vorhanden
if [ -z "$BILLING_ACCOUNT_ID" ]; then
    # Versuche automatische Erkennung
    if auto_detect_billing_account; then
        echo ""
        read -p "Automatisch erkannten Billing Account verwenden? (J/n): " use_auto
        if [[ "$use_auto" =~ ^[nN] ]]; then
            BILLING_ACCOUNT_ID=""
        fi
    fi
    
    # Falls immer noch leer, manuelle Eingabe
    if [ -z "$BILLING_ACCOUNT_ID" ]; then
        print_step "Verfügbare Billing Accounts:"
        gcloud alpha billing accounts list
        echo ""
        read -p "Geben Sie die Billing Account ID ein: " BILLING_ACCOUNT_ID
    fi
else
    print_step "Verwende gespeicherte Billing Account ID: $BILLING_ACCOUNT_ID"
fi

print_step "Verknüpfe Billing Account mit Projekt..."
if retry_with_backoff gcloud alpha billing projects link "$GCP_PROJECT" --billing-account="$BILLING_ACCOUNT_ID"; then
    print_step "Billing Account erfolgreich verknüpft ✓"
    
    # Aktualisiere Konfigurationsdatei
    save_config_file
else
    print_error "Billing Account Verknüpfung fehlgeschlagen"
    exit 1
fi

# Step 8: Create Service Account
print_header "Schritt 8: Service Account erstellen"
print_step "Erstelle Service Account: $GCP_SA"

if gcloud iam service-accounts describe "$GCP_SA@$GCP_PROJECT.iam.gserviceaccount.com" &>/dev/null; then
    print_warning "Service Account $GCP_SA existiert bereits"
else
    gcloud iam service-accounts create "$GCP_SA" \
        --display-name="OpenShift 4 Service Account"
    print_step "Service Account erstellt ✓"
fi

print_step "Weise Owner-Rolle zu..."
gcloud projects add-iam-policy-binding "$GCP_PROJECT" \
    --member="serviceAccount:$GCP_SA@$GCP_PROJECT.iam.gserviceaccount.com" \
    --role="roles/owner"

print_step "Service Account konfiguriert ✓"

# Step 9: DNS Configuration
print_header "Schritt 9: DNS Zone erstellen"
print_step "Erstelle DNS Zone für Domain: $GCP_DOMAIN"

DNS_ZONE_NAME=$(echo "$GCP_DOMAIN" | tr '.' '-')

if gcloud dns managed-zones describe "$DNS_ZONE_NAME" &>/dev/null; then
    print_warning "DNS Zone $DNS_ZONE_NAME existiert bereits"
else
    gcloud dns managed-zones create "$DNS_ZONE_NAME" \
        --dns-name="$GCP_DOMAIN" \
        --description="OpenShift 4 DNS Zone"
    print_step "DNS Zone erstellt ✓"
fi

print_step "DNS Name Server für die Zone:"
gcloud dns managed-zones describe "$DNS_ZONE_NAME" --format="value(nameServers[].join(' '))"

echo ""
print_warning "WICHTIG: DNS Delegation erforderlich!"
echo "Sie müssen die oben angezeigten Name Server in Ihren Domain-Provider eintragen."
echo "Wenn Sie eine Subdomain delegieren (z.B. gcp.ihredomain.com), erstellen Sie NS-Records"
echo "in der Parent-Domain für die Subdomain mit den angezeigten Name Servern."
echo ""
wait_for_user "Haben Sie die DNS Delegation konfiguriert?"

# Step 10: Automated Quota Check
print_header "Schritt 10: Automatische Quota-Prüfung"

# Prüfe Quotas automatisch
if check_quotas_automatically; then
    print_step "Alle Quotas sind ausreichend für OpenShift Installation ✓"
else
    print_warning "Quotas möglicherweise unzureichend"
    echo ""
    echo "Empfohlene Mindestquotas für OpenShift:"
    echo "- CPUs: 40"
    echo "- SSD Storage: 950 GB"
    echo ""
    echo "Falls eine Quota-Erhöhung erforderlich ist:"
    echo "1. Gehen Sie zu: https://console.cloud.google.com/iam-admin/quotas"
    echo "2. Wählen Sie Ihr Projekt: $GCP_PROJECT"
    echo "3. Wählen Sie Region: $GCP_REGION"
    echo "4. Suchen Sie nach 'Compute Engine API CPUs' und erhöhen Sie auf 40"
    echo "5. Suchen Sie nach 'Compute Engine API Persistent Disk SSD (GB)' und erhöhen Sie auf 950"
    echo "6. Geben Sie eine Begründung an (z.B. 'OpenShift 4 Installation')"
    echo "7. Reichen Sie die Anfrage ein"
    echo ""
    echo "⏰ Die Quota-Erhöhung kann 1-2 Werktage dauern!"
    echo ""
    
    read -p "Trotzdem fortfahren? (Nicht empfohlen) (j/N): " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[jJyY] ]]; then
        print_warning "Installation abgebrochen. Bitte erhöhen Sie die Quotas und führen Sie das Script erneut aus."
        exit 1
    fi
fi

# Step 11: Service Account Credentials
print_header "Schritt 11: Service Account Credentials verwalten"

# Definiere Standard-Pfade
DEFAULT_JSON_PATH="$HOME/.gcp/osServiceAccount.json"
DEFAULT_SA_EMAIL="$GCP_SA@$GCP_PROJECT.iam.gserviceaccount.com"

print_step "Erstelle .gcp Verzeichnis..."
mkdir -p ~/.gcp

# Prüfe ob Service Account existiert
if ! check_service_account_exists "$DEFAULT_SA_EMAIL"; then
    print_error "Service Account $DEFAULT_SA_EMAIL existiert nicht!"
    echo "Bitte führen Sie zuerst Schritt 8 aus oder erstellen Sie den Service Account manuell."
    exit 1
fi

print_step "Service Account gefunden: $DEFAULT_SA_EMAIL ✓"

# Prüfe ob bereits eine JSON Datei existiert
if [ -f "$DEFAULT_JSON_PATH" ]; then
    print_warning "Service Account JSON bereits vorhanden: $DEFAULT_JSON_PATH"
    
    # Validiere existierende JSON Datei
    if validate_service_account_json "$DEFAULT_JSON_PATH"; then
        echo ""
        echo "Optionen:"
        echo "1) Vorhandene JSON Datei verwenden"
        echo "2) Neuen Schlüssel erstellen (alte Datei wird gesichert)"
        echo "3) Anderen Service Account auswählen"
        echo "4) Benutzerdefinierten Pfad angeben"
        echo ""
        read -p "Wählen Sie eine Option (1-4) [1]: " json_option
        json_option=${json_option:-1}
        
        case $json_option in
            1)
                print_step "Verwende vorhandene JSON Datei ✓"
                SERVICE_ACCOUNT_JSON="$DEFAULT_JSON_PATH"
                ;;
            2)
                if create_service_account_key "$DEFAULT_SA_EMAIL" "$DEFAULT_JSON_PATH" true; then
                    SERVICE_ACCOUNT_JSON="$DEFAULT_JSON_PATH"
                else
                    print_error "Fehler beim Erstellen des neuen Schlüssels"
                    exit 1
                fi
                ;;
            3)
                if selected_sa=$(interactive_service_account_selection); then
                    print_step "Ausgewählter Service Account: $selected_sa"
                    if create_service_account_key "$selected_sa" "$DEFAULT_JSON_PATH" true; then
                        SERVICE_ACCOUNT_JSON="$DEFAULT_JSON_PATH"
                    else
                        print_error "Fehler beim Erstellen des Schlüssels für $selected_sa"
                        exit 1
                    fi
                else
                    print_error "Service Account Auswahl fehlgeschlagen"
                    exit 1
                fi
                ;;
            4)
                read -p "Geben Sie den Pfad zur JSON Datei an: " custom_json_path
                if [ -f "$custom_json_path" ] && validate_service_account_json "$custom_json_path"; then
                    SERVICE_ACCOUNT_JSON="$custom_json_path"
                    print_step "Verwende benutzerdefinierte JSON Datei: $custom_json_path ✓"
                else
                    read -p "Datei nicht gefunden oder ungültig. Neuen Schlüssel an diesem Pfad erstellen? (j/N): " create_new
                    if [[ "$create_new" =~ ^[jJyY] ]]; then
                        mkdir -p "$(dirname "$custom_json_path")"
                        if create_service_account_key "$DEFAULT_SA_EMAIL" "$custom_json_path" false; then
                            SERVICE_ACCOUNT_JSON="$custom_json_path"
                        else
                            print_error "Fehler beim Erstellen der JSON Datei"
                            exit 1
                        fi
                    else
                        print_error "Keine gültige JSON Datei verfügbar"
                        exit 1
                    fi
                fi
                ;;
            *)
                print_error "Ungültige Option"
                exit 1
                ;;
        esac
    else
        print_warning "Vorhandene JSON Datei ist ungültig oder beschädigt"
        read -p "Neuen Schlüssel erstellen? (J/n): " recreate_key
        if [[ ! "$recreate_key" =~ ^[nN] ]]; then
            if create_service_account_key "$DEFAULT_SA_EMAIL" "$DEFAULT_JSON_PATH" true; then
                SERVICE_ACCOUNT_JSON="$DEFAULT_JSON_PATH"
            else
                print_error "Fehler beim Erstellen des neuen Schlüssels"
                exit 1
            fi
        else
            print_error "Keine gültige Service Account JSON verfügbar"
            exit 1
        fi
    fi
else
    # Keine JSON Datei vorhanden, erstelle neue
    print_step "Erstelle neuen Service Account Schlüssel..."
    if create_service_account_key "$DEFAULT_SA_EMAIL" "$DEFAULT_JSON_PATH" false; then
        SERVICE_ACCOUNT_JSON="$DEFAULT_JSON_PATH"
    else
        print_error "Fehler beim Erstellen des Service Account Schlüssels"
        
        # Fallback: Versuche interaktive Auswahl
        print_step "Versuche alternative Service Account Auswahl..."
        if selected_sa=$(interactive_service_account_selection); then
            if create_service_account_key "$selected_sa" "$DEFAULT_JSON_PATH" false; then
                SERVICE_ACCOUNT_JSON="$DEFAULT_JSON_PATH"
            else
                print_error "Auch alternative Service Account Schlüsselerstellung fehlgeschlagen"
                exit 1
            fi
        else
            exit 1
        fi
    fi
fi

# Zeige Informationen über die verwendete JSON Datei
echo ""
print_step "Service Account Credentials konfiguriert ✓"
echo "  JSON Datei: $SERVICE_ACCOUNT_JSON"
echo "  Dateigröße: $(stat -c%s "$SERVICE_ACCOUNT_JSON" 2>/dev/null || echo "Unbekannt") Bytes"
echo "  Berechtigungen: $(stat -c%A "$SERVICE_ACCOUNT_JSON" 2>/dev/null || echo "Unbekannt")"

# Erstelle Umgebungsvariable für OpenShift Installation
export GOOGLE_CREDENTIALS="$SERVICE_ACCOUNT_JSON"
echo "  Umgebungsvariable GOOGLE_CREDENTIALS gesetzt ✓"

# Speichere aktualisierte Konfiguration mit Service Account JSON Pfad
save_config_file

# Zeige aktuelle Service Account Schlüssel (begrenzt)
echo ""
print_step "Aktuelle Schlüssel für diesen Service Account:"
list_service_account_keys "$(grep -o '"client_email":"[^"]*"' "$SERVICE_ACCOUNT_JSON" | cut -d'"' -f4 2>/dev/null || echo "$DEFAULT_SA_EMAIL")"

# Red Hat Console Integration Hinweise
echo ""
print_step "📋 Red Hat Console Integration:"
echo "  Für die Registrierung bei Red Hat OpenShift benötigen Sie diese JSON Datei:"
echo "  Pfad: $SERVICE_ACCOUNT_JSON"
echo ""
echo "  Schritte zur Verwendung mit Red Hat Console:"
echo "  1. Gehen Sie zu https://console.redhat.com/openshift"
echo "  2. Wählen Sie 'Create cluster' > 'Google Cloud'"
echo "  3. Laden Sie die JSON Datei hoch: $SERVICE_ACCOUNT_JSON"
echo "  4. Folgen Sie den weiteren Anweisungen der Red Hat Console"
echo ""

# Step 12: Automated DNS Propagation Monitoring
print_header "Schritt 12: Automatische DNS Propagation Überwachung"

# Versuche automatisches DNS Monitoring
print_step "Starte automatische DNS Propagation Überwachung..."
if monitor_dns_propagation "$GCP_DOMAIN"; then
    print_step "DNS Propagation erfolgreich validiert ✓"
else
    print_warning "DNS Propagation Monitoring abgeschlossen, aber möglicherweise noch nicht vollständig"
    echo ""
    read -p "Trotzdem mit der Installation fortfahren? (j/N): " continue_dns
    if [[ ! "$continue_dns" =~ ^[jJyY] ]]; then
        print_warning "Installation pausiert. Prüfen Sie die DNS Delegation und führen Sie das Script erneut aus."
        echo "Zur manuellen Prüfung verwenden Sie: dig NS $GCP_DOMAIN"
        exit 1
    fi
fi

# Step 13: Prepare Installation
print_header "Schritt 13: OpenShift Installation vorbereiten"
print_step "Erstelle Installationsverzeichnis..."
INSTALL_DIR="openshift-install-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

print_step "Installationsverzeichnis: $(pwd)"

# Step 14: Check Pull Secret
print_header "Schritt 14: Pull Secret prüfen"
if [ ! -f "../pull-secret.txt" ]; then
    print_error "pull-secret.txt nicht gefunden!"
    echo "Bitte laden Sie Ihr Pull Secret von https://try.openshift.com herunter"
    echo "und speichern Sie es als 'pull-secret.txt' im Hauptverzeichnis."
    exit 1
fi

print_step "Pull Secret gefunden ✓"

# Step 14.5: SSH Key Setup
print_header "Schritt 14.5: SSH Key Konfiguration"

# SSH Key automatisch erkennen oder generieren
if ! auto_detect_ssh_key; then
    read -p "Neuen SSH Key generieren? (J/n): " generate_key
    if [[ ! "$generate_key" =~ ^[nN] ]]; then
        if generate_ssh_key; then
            print_step "SSH Key erfolgreich generiert und konfiguriert ✓"
        else
            print_error "SSH Key Generierung fehlgeschlagen"
            exit 1
        fi
    else
        print_warning "Kein SSH Key konfiguriert. OpenShift Installation wird nach SSH Key fragen."
    fi
else
    print_step "SSH Key automatisch konfiguriert: $SSH_KEY_PATH ✓"
fi

# Step 15: Run OpenShift Installer
print_header "Schritt 15: Automatisierte OpenShift Installation"
print_step "Vorbereitung der automatisierten Installation..."
echo ""
echo "Folgende Konfiguration wird verwendet:"
echo "  Platform: gcp"
echo "  Project ID: $GCP_PROJECT"
echo "  Region: $GCP_REGION (Frankfurt)"
echo "  Base Domain: $GCP_DOMAIN"
echo "  SSH Key: ${SSH_KEY_PATH:-'Wird interaktiv abgefragt'}"
echo ""
print_warning "Die Installation dauert etwa 30-40 Minuten!"
echo ""
wait_for_user "Sind Sie bereit, die Installation zu starten?"

print_step "Starte OpenShift Installation..."
# Verwende die bereits konfigurierte SERVICE_ACCOUNT_JSON Variable
export GOOGLE_CREDENTIALS="$SERVICE_ACCOUNT_JSON"

# Setze GCP als Standard-Projekt für den Installer
gcloud config set project "$GCP_PROJECT"

# Validiere Service Account JSON vor der Installation
print_step "Validiere Service Account Credentials für Installation..."
if ! validate_service_account_json "$SERVICE_ACCOUNT_JSON"; then
    print_error "Service Account JSON Validierung fehlgeschlagen"
    exit 1
fi

if retry_with_backoff openshift-install create cluster --dir . --log-level=info; then
    print_step "OpenShift Installation erfolgreich gestartet ✓"
else
    print_error "OpenShift Installation fehlgeschlagen"
    print_warning "Prüfen Sie die Logs und versuchen Sie es erneut"
    exit 1
fi

# Step 16: Installation Complete
print_header "Schritt 16: Installation abgeschlossen!"
print_step "Installation erfolgreich abgeschlossen ✓"

echo ""
print_step "Cluster-Informationen:"
cat auth/kubeconfig | grep server || echo "Kubeconfig nicht gefunden"

if [ -f auth/kubeadmin-password ]; then
    print_step "Webkonsole Zugangsdaten:"
    echo "Username: kubeadmin"
    echo "Password: $(cat auth/kubeadmin-password)"
fi

print_step "Konfiguriere kubectl/oc Zugang..."
export KUBECONFIG="$(pwd)/auth/kubeconfig"
echo "export KUBECONFIG=$(pwd)/auth/kubeconfig" >> ~/.bashrc

print_step "Teste Cluster-Verbindung..."
oc get nodes
oc get sc
oc get clusterversion

print_header "Installation erfolgreich abgeschlossen!"
echo "Ihr OpenShift 4 Cluster ist bereit!"
echo ""
echo "🎉 INSTALLATION ERFOLGREICH! 🎉"
echo ""
echo "📋 Wichtige Cluster-Informationen:"
echo "├── Kubeconfig: $(pwd)/auth/kubeconfig"
echo "├── Admin Password: $(cat auth/kubeadmin-password 2>/dev/null || echo 'Siehe auth/kubeadmin-password')"
echo "├── Webkonsole URL: Siehe Installations-Output oben"
echo "├── Service Account JSON: ${SERVICE_ACCOUNT_JSON:-'Nicht konfiguriert'}"
echo "└── SSH Key: ${SSH_KEY_PATH:-'Nicht konfiguriert'}"
echo ""
echo "🔧 Nächste Schritte:"
echo "1. Fügen Sie 'export KUBECONFIG=$(pwd)/auth/kubeconfig' zu Ihrer ~/.bashrc hinzu"
echo "2. Loggen Sie sich in die OpenShift Webkonsole ein"
echo "3. Erkunden Sie Ihren neuen OpenShift Cluster!"
echo ""
echo "🌐 Red Hat Console Integration:"
echo "Für erweiterte Verwaltung und Support können Sie Ihren Cluster mit der Red Hat Console verknüpfen:"
echo ""
echo "📝 Red Hat Console Setup:"
echo "├── URL: https://console.redhat.com/openshift"
echo "├── Aktion: 'Add existing cluster' oder 'Register cluster'"
echo "├── Service Account JSON: ${SERVICE_ACCOUNT_JSON:-'Nicht verfügbar'}"
echo "├── Cluster ID: Verfügbar in der OpenShift Webkonsole unter 'Administration' > 'Cluster Settings'"
echo "└── Pull Secret: ../pull-secret.txt (falls noch benötigt)"
echo ""
echo "📊 Red Hat Console Funktionen:"
echo "├── Cluster-Monitoring und Alerts"
echo "├── Update-Management"
echo "├── Support-Cases erstellen"
echo "├── Compliance und Security Scans"
echo "└── Cost Management und Insights"
echo ""
echo "🛡️  Sicherheitshinweise:"
echo "├── Service Account JSON sicher aufbewahren: ${SERVICE_ACCOUNT_JSON:-'N/A'}"
echo "├── Regelmäßige Passwort-Rotation für kubeadmin"
echo "├── Backup der Kubeconfig-Datei erstellen"
echo "└── Cluster-Monitoring aktivieren"
echo ""
echo "📁 Dateien für Red Hat Support:"
if [ -f "${SERVICE_ACCOUNT_JSON:-}" ]; then
    echo "├── Service Account JSON: ${SERVICE_ACCOUNT_JSON} ✓"
else
    echo "├── Service Account JSON: Nicht verfügbar ❌"
fi
if [ -f "$(pwd)/auth/kubeconfig" ]; then
    echo "├── Kubeconfig: $(pwd)/auth/kubeconfig ✓"
else
    echo "├── Kubeconfig: Nicht verfügbar ❌"
fi
if [ -f "../pull-secret.txt" ]; then
    echo "├── Pull Secret: $(pwd)/../pull-secret.txt ✓"
else
    echo "├── Pull Secret: Nicht verfügbar ❌"
fi
echo "└── Installation Log: $LOG_FILE ✓"
echo ""
print_step "🎯 Zusätzliche Ressourcen:"
echo "├── OpenShift Dokumentation: https://docs.openshift.com/"
echo "├── Red Hat Learning: https://learn.openshift.com/"
echo "├── Community Forum: https://community.redhat.com/"
echo "└── Support Portal: https://access.redhat.com/"
echo ""
print_step "Installation Log gespeichert in: $LOG_FILE"