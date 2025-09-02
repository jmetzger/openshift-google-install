# OpenShift 4 Installation auf Google Cloud

Dieses Repository enthält ein interaktives Script zur schrittweisen Installation von OpenShift 4 auf Google Cloud Platform.

## 📹 Video-Anleitung

Die Installation basiert auf dem offiziellen Red Hat Training Video:
**[OpenShift 4.2 on Google Cloud Installation](https://www.youtube.com/watch?v=qMJugiru-tA)**

Das komplette Transkript des Videos finden Sie in [`transcript.txt`](transcript.txt).

## 🚀 Schnellstart

```bash
./install.sh
```

Das Script führt Sie interaktiv durch alle erforderlichen Schritte.

## 📋 Voraussetzungen

### Automatisch geprüft:
- `gcloud` CLI
- `oc` CLI  
- `openshift-install` Binary

### Manuell vorzubereiten:
1. **Google Cloud Account** mit aktivem Billing Account
2. **Red Hat Account** für try.openshift.com
3. **DNS Domain** (kann über Google oder externen Provider verwaltet werden)
4. **Pull Secret** von https://console.redhat.com/openshift/install/pull-secret (oder https://try.openshift.com)

## 🔧 Installation Übersicht

### Automatische Schritte:
1. ✅ Voraussetzungen prüfen
2. ✅ gcloud CLI initialisieren  
3. ✅ Umgebungsvariablen konfigurieren
4. ✅ Google Cloud Projekt erstellen
5. ✅ APIs aktivieren (10+ erforderliche APIs)
6. ✅ Billing Account verknüpfen
7. ✅ Service Account erstellen mit Owner-Rolle
8. ✅ DNS Zone erstellen
9. ✅ Service Account Credentials herunterladen
10. ✅ OpenShift Installation durchführen
11. ✅ Cluster-Zugriff konfigurieren

### Manuelle Schritte (mit Enter-Pausen):
- 🔄 **Quota-Erhöhung beantragen** (40 CPUs, 950GB SSD)
- 🔄 **DNS Delegation konfigurieren** (Nameserver in Domain-Provider eintragen)
- 🔄 **Pull Secret bereitstellen** (als `pull-secret.txt`)

## 📁 Erforderliche Dateien

Stellen Sie sicher, dass diese Datei im Projektverzeichnis vorhanden ist:
- `pull-secret.txt` - Ihr OpenShift Pull Secret von try.openshift.com

## ⚠️ Wichtige Hinweise

### Quotas
Die Standard-Quotas in Google Cloud reichen nicht für OpenShift aus. Sie müssen folgende Quotas erhöhen:
- **CPUs**: 40 (für die gewählte Region)
- **Persistent Disk SSD**: 950 GB (für die gewählte Region)

**⏰ Bearbeitungszeit**: 1-2 Werktage

### DNS Konfiguration
Das Script erstellt eine DNS Zone in Google Cloud und zeigt Ihnen die Nameserver an. Sie müssen:
- Bei **eigener Domain**: NS-Records für Subdomain erstellen
- Bei **Google Domain**: Automatisch konfiguriert

### Kosten
OpenShift auf Google Cloud verursacht laufende Kosten:
- Compute-Instanzen (3 Master + 3 Worker Nodes)
- Persistent Storage
- Load Balancer
- Netzwerk-Traffic

## 🗂️ Nach der Installation

Das Script erstellt folgende Struktur:
```
openshift-install-YYYYMMDD-HHMMSS/
├── auth/
│   ├── kubeconfig          # Cluster-Zugriff
│   └── kubeadmin-password  # Admin-Passwort
├── terraform/              # Terraform-Dateien
└── metadata.json          # Cluster-Metadaten
```

### Cluster-Zugriff konfigurieren:
```bash
export KUBECONFIG=./openshift-install-*/auth/kubeconfig
oc get nodes
```

### Webkonsole-Zugriff:
- URL: Siehe Installations-Output
- Username: `kubeadmin`  
- Password: Inhalt von `auth/kubeadmin-password`

## 🔍 Troubleshooting

### Häufige Probleme:

**1. Quota-Fehler**
```
ERROR: Quota exceeded
```
→ Prüfen Sie die Quota-Limits in der Google Cloud Console

**2. DNS-Propagation**
```
ERROR: DNS resolution failed
```
→ Warten Sie auf DNS-Propagation (kann bis zu 24h dauern)

**3. API nicht aktiviert**
```
ERROR: API not enabled
```
→ Das Script aktiviert alle APIs automatisch, warten Sie einen Moment

**4. Billing Account**
```
ERROR: Billing account required
```
→ Verknüpfen Sie ein aktives Billing Account mit Ihrem Projekt

### Logs
Alle Aktionen werden in `openshift-install.log` protokolliert.

## 📚 Weiterführende Ressourcen

- [OpenShift Documentation](https://docs.openshift.com/)
- [Google Cloud OpenShift](https://cloud.google.com/solutions/partners/openshift-on-gcp)
- [Red Hat OpenShift Try](https://try.openshift.com/)
- [Original Video Tutorial](https://www.youtube.com/watch?v=qMJugiru-tA)

## 🆘 Support

Bei Problemen prüfen Sie:
1. Das Installations-Log `openshift-install.log`
2. Das Video-Transkript in `transcript.txt`
3. Die offizielle OpenShift-Dokumentation

## Deinstallation 

```
Ins Installationsverzeichnis wechsel 
-> dann

openshift_install destroy cluster 
```


---

**Hinweis**: Dieses Script basiert auf OpenShift 4.2 (Tech Preview). Für Produktionsumgebungen verwenden Sie die aktuelle GA-Version.
