# Enabling scc - a bit hacky, but works (tested with different namespaces) 

   * Script to set scc (Security Context Contraints)
   * Like: A container is not allowed to run as non-root 

```bash
#!/bin/bash

# OpenShift Security Configuration Script
# Verhindert das Ausführen von Pods als root User

echo "=== OpenShift Security Configuration Script ==="
echo "Dieses Script konfiguriert Sicherheitsrichtlinien für dein OCP Cluster"
echo ""

# Prüfe ob oc CLI verfügbar ist
if ! command -v oc &> /dev/null; then
    echo "ERROR: oc CLI nicht gefunden. Bitte installiere die OpenShift CLI."
    exit 1
fi

# Prüfe ob User eingeloggt ist
if ! oc whoami &> /dev/null; then
    echo "ERROR: Nicht in OpenShift eingeloggt. Bitte mit 'oc login' einloggen."
    exit 1
fi

echo "Eingeloggt als: $(oc whoami)"
echo ""

# 1. Erstelle eine custom SCC die kein root erlaubt
echo "1. Erstelle Custom Security Context Constraint..."
cat <<EOF > no-root-scc.yaml
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: no-root-scc
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegeEscalation: false
allowPrivilegedContainer: false
allowedCapabilities: null
defaultAddCapabilities: null
fsGroup:
  type: MustRunAs
  ranges:
    - min: 1000
      max: 65535
priority: 10
readOnlyRootFilesystem: false
requiredDropCapabilities:
- ALL
runAsUser:
  type: MustRunAsRange
  uidRangeMin: 1000
  uidRangeMax: 65535
seLinuxContext:
  type: MustRunAs
supplementalGroups:
  type: RunAsAny
users: []
groups: []
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
EOF

oc apply -f no-root-scc.yaml
echo "✓ Custom SCC erstellt"
echo ""

# 2. Erstelle eine ClusterRole für die SCC
echo "2. Erstelle ClusterRole für SCC..."
cat <<EOF > no-root-clusterrole.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: use-no-root-scc
rules:
- apiGroups:
  - security.openshift.io
  resourceNames:
  - no-root-scc
  resources:
  - securitycontextconstraints
  verbs:
  - use
EOF

oc apply -f no-root-clusterrole.yaml
echo "✓ ClusterRole erstellt"
echo ""

# 3. Frage nach dem Namespace
read -p "In welchem Namespace soll die Richtlinie angewendet werden? (oder 'all' für alle): " NAMESPACE

if [ "$NAMESPACE" == "all" ]; then
    # Wende auf alle Service Accounts in allen Namespaces an
    echo "3. Wende SCC auf alle Namespaces an..."

    # Erstelle ClusterRoleBinding
    cat <<EOF > no-root-clusterrolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: no-root-scc-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: use-no-root-scc
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:authenticated
EOF

    oc apply -f no-root-clusterrolebinding.yaml
    echo "✓ SCC auf alle Namespaces angewendet"
else
    # Wende nur auf spezifischen Namespace an
    echo "3. Wende SCC auf Namespace '$NAMESPACE' an..."

    # Prüfe ob Namespace existiert
    if ! oc get namespace "$NAMESPACE" &> /dev/null; then
        echo "ERROR: Namespace '$NAMESPACE' existiert nicht."
        exit 1
    fi

    # Erstelle RoleBinding für den spezifischen Namespace
    cat <<EOF > no-root-rolebinding-$NAMESPACE.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: no-root-scc-binding
  namespace: $NAMESPACE
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: use-no-root-scc
subjects:
- kind: ServiceAccount
  name: default
  namespace: $NAMESPACE
EOF

    oc apply -f no-root-rolebinding-$NAMESPACE.yaml
    echo "✓ SCC auf Namespace '$NAMESPACE' angewendet"
fi

echo ""

# 4. Entferne die Standard privileged SCC von Usern (optional)
echo "4. Möchtest du die 'privileged' SCC von normalen Usern entfernen? (empfohlen)"
read -p "Fortfahren? (y/n): " REMOVE_PRIV

if [ "$REMOVE_PRIV" == "y" ]; then
    echo "Entferne privileged SCC von authenticated users..."
    oc adm policy remove-scc-from-group privileged system:authenticated
    echo "✓ Privileged SCC entfernt"
fi

echo ""

# 5. Test Pod erstellen
echo "5. Möchtest du einen Test-Pod erstellen um die Konfiguration zu prüfen?"
read -p "Test durchführen? (y/n): " RUN_TEST

if [ "$RUN_TEST" == "y" ]; then
    if [ "$NAMESPACE" == "all" ]; then
        TEST_NS="default"
    else
        TEST_NS="$NAMESPACE"
    fi

    echo "Erstelle Test-Pod der als root laufen will (sollte fehlschlagen)..."
    cat <<EOF > test-root-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-root-pod
  namespace: $TEST_NS
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
    securityContext:
      runAsUser: 0
EOF

    if oc apply -f test-root-pod.yaml 2>&1; then
        echo "⚠️  WARNUNG: Pod wurde erstellt! Prüfe die SCC-Konfiguration."
        oc delete pod test-root-pod -n $TEST_NS
    else
        echo "✓ Gut! Pod wurde wie erwartet abgelehnt."
    fi

    echo ""
    echo "Erstelle Test-Pod der als non-root läuft (sollte funktionieren)..."
    cat <<EOF > test-nonroot-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-nonroot-pod
  namespace: $TEST_NS
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
    securityContext:
      runAsUser: 1000
      runAsGroup: 1000
EOF

    if oc apply -f test-nonroot-pod.yaml; then
        echo "✓ Erfolg! Non-root Pod wurde erstellt."
        echo "Prüfe Pod Status:"
        oc get pod test-nonroot-pod -n $TEST_NS
        echo ""
        echo "Aufräumen..."
        oc delete pod test-nonroot-pod -n $TEST_NS
    else
        echo "⚠️  ERROR: Non-root Pod konnte nicht erstellt werden. Prüfe die Konfiguration."
    fi
fi

echo ""
echo "=== Zusammenfassung ==="
echo "✓ Custom SCC 'no-root-scc' wurde erstellt"
echo "✓ Diese verhindert das Ausführen von Pods als root (UID 0)"
echo "✓ Erlaubte UIDs: 1000-65535"

if [ "$NAMESPACE" == "all" ]; then
    echo "✓ SCC wurde auf alle Namespaces angewendet"
else
    echo "✓ SCC wurde auf Namespace '$NAMESPACE' angewendet"
fi

echo ""
echo "Nützliche Befehle:"
echo "- Zeige alle SCCs: oc get scc"
echo "- Zeige Details einer SCC: oc describe scc no-root-scc"
echo "- Prüfe welche SCC ein Pod nutzt: oc get pod <pod-name> -o yaml | grep scc"
echo "- Zeige SCC Bindings: oc get rolebindings,clusterrolebindings | grep scc"

echo ""
echo "Aufräumen der temporären Dateien..."
rm -f no-root-scc.yaml no-root-clusterrole.yaml no-root-clusterrolebinding.yaml no-root-rolebinding-*.yaml test-root-pod.yaml test-nonroot-pod.yaml
echo "✓ Fertig!"
```
