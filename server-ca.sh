#!/usr/bin/env bash
# =============================================================================
# server-ca.sh — Serveur HTTPS de test pour une PKI générée par quick-ca.sh
#
# Ce script :
#   1. Vérifie la résolution DNS du domaine dans /etc/hosts
#   2. Lance un mini-serveur HTTPS sur le port choisi
#   3. Affiche les commandes de diagnostic
#
# Usage : ./server-ca.sh [répertoire-pki]
#         ./server-ca.sh ./pki-web.lab.local
#
# Pré-requis : python3
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

# Répertoire contenant les fichiers générés par quick-ca.sh
PKI_DIR="${1:-./pki-web.lab.local}"

# Port du serveur HTTPS de test
PORT=8443

# Page HTML de test à servir (créée automatiquement)
SERVE_DIR="${PKI_DIR}/_www"

# ─────────────────────────────────────────────────────────────────────────────
# FIN DE LA CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'
YELLOW=$'\033[0;33m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

info()  { printf "${CYAN}[INFO]${RESET}  %s\n" "$*"; }
ok()    { printf "${GREEN}[OK]${RESET}    %s\n" "$*"; }
warn()  { printf "${YELLOW}[AVIS]${RESET}  %s\n" "$*"; }
fail()  { printf "${RED}[ERREUR]${RESET} %s\n" "$*" >&2; exit 1; }
header(){ printf "\n${BOLD}── %s ──${RESET}\n\n" "$*"; }

# ── Vérifications ────────────────────────────────────────────────────────────

[[ -d "${PKI_DIR}" ]]            || fail "Répertoire PKI introuvable : ${PKI_DIR}"
[[ -f "${PKI_DIR}/ca.crt" ]]     || fail "ca.crt introuvable dans ${PKI_DIR}"
[[ -f "${PKI_DIR}/server.crt" ]] || fail "server.crt introuvable dans ${PKI_DIR}"
[[ -f "${PKI_DIR}/server.key" ]] || fail "server.key introuvable dans ${PKI_DIR}"
command -v python3 >/dev/null 2>&1 || fail "python3 introuvable."

# Extraire le CN (domaine) depuis le certificat serveur
DOMAIN=$(openssl x509 -in "${PKI_DIR}/server.crt" -noout -subject \
    | sed -n 's/.*CN *= *//p')
info "Domaine détecté dans le certificat : ${DOMAIN}"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 1 : Vérifier /etc/hosts
# ══════════════════════════════════════════════════════════════════════════════

header "Résolution DNS"

if grep -qE "^\s*127\.0\.0\.1\s+.*${DOMAIN}" /etc/hosts 2>/dev/null; then
    ok "${DOMAIN} pointe déjà vers 127.0.0.1 dans /etc/hosts"
else
    warn "${DOMAIN} absent de /etc/hosts"
    echo ""
    printf "  Ajouter cette ligne à /etc/hosts :\n"
    printf "  ${BOLD}127.0.0.1   ${DOMAIN}${RESET}\n\n"
    printf "  Commande rapide :\n"
    printf "  ${CYAN}echo '127.0.0.1   ${DOMAIN}' | sudo tee -a /etc/hosts${RESET}\n\n"
fi

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 2 : Créer une page de test
# ══════════════════════════════════════════════════════════════════════════════

mkdir -p "${SERVE_DIR}"
cat > "${SERVE_DIR}/index.html" <<HTML
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Test TLS — ${DOMAIN}</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: system-ui, -apple-system, sans-serif;
            background: #0f172a; color: #e2e8f0;
            display: flex; align-items: center; justify-content: center;
            min-height: 100vh;
        }
        .card {
            background: #1e293b; border-radius: 12px; padding: 2.5rem;
            max-width: 600px; width: 90%; box-shadow: 0 4px 24px rgba(0,0,0,0.3);
        }
        .status { display: flex; align-items: center; gap: 0.75rem; margin-bottom: 1.5rem; }
        .dot {
            width: 16px; height: 16px; border-radius: 50%;
            background: #22c55e; box-shadow: 0 0 8px #22c55e;
        }
        h1 { font-size: 1.5rem; font-weight: 600; }
        table { width: 100%; border-collapse: collapse; margin-top: 1rem; }
        td { padding: 0.5rem 0; border-bottom: 1px solid #334155; }
        td:first-child { color: #94a3b8; width: 40%; }
        .footer { margin-top: 1.5rem; font-size: 0.85rem; color: #64748b; }
    </style>
</head>
<body>
    <div class="card">
        <div class="status"><div class="dot"></div><h1>TLS fonctionne !</h1></div>
        <table>
            <tr><td>Domaine</td><td>${DOMAIN}</td></tr>
            <tr><td>Protocole</td><td id="proto">—</td></tr>
            <tr><td>Port</td><td>${PORT}</td></tr>
            <tr><td>Cadenas</td><td id="lock">Vérifiez dans la barre d'adresse ↑</td></tr>
        </table>
        <p class="footer">
            Si cette page s'affiche <strong>sans avertissement</strong> et avec un
            cadenas dans la barre d'adresse, l'AC a été correctement importée et
            le certificat serveur est valide.
        </p>
    </div>
    <script>
        document.getElementById('proto').textContent = location.protocol;
    </script>
</body>
</html>
HTML
ok "Page de test créée"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 3 : Serveur HTTPS éphémère (Python)
# ══════════════════════════════════════════════════════════════════════════════

header "Serveur HTTPS de test"

# Script Python inline — plus fiable que openssl s_server pour servir du HTTP
PYTHON_SERVER=$(cat <<'PYEOF'
import http.server, ssl, sys, os

port     = int(sys.argv[1])
certfile = sys.argv[2]
keyfile  = sys.argv[3]
cafile   = sys.argv[4]
webdir   = sys.argv[5]

os.chdir(webdir)

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(certfile=certfile, keyfile=keyfile)
# Charger la CA dans la chaîne envoyée au client (aide au debug)
ctx.load_verify_locations(cafile=cafile)

handler = http.server.SimpleHTTPRequestHandler
httpd   = http.server.HTTPServer(("0.0.0.0", port), handler)
httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)

print(f"Serveur HTTPS actif → https://localhost:{port}/", flush=True)
print("Ctrl+C pour arrêter.\n", flush=True)
try:
    httpd.serve_forever()
except KeyboardInterrupt:
    print("\nServeur arrêté.")
    httpd.server_close()
PYEOF
)

# Résoudre les chemins absolus pour Python
CERT_ABS=$(realpath "${PKI_DIR}/server.crt")
KEY_ABS=$(realpath "${PKI_DIR}/server.key")
CA_ABS=$(realpath "${PKI_DIR}/ca.crt")
WWW_ABS=$(realpath "${SERVE_DIR}")

echo ""
printf "  ${BOLD}URL de test :${RESET}  ${GREEN}https://${DOMAIN}:${PORT}/${RESET}\n"
printf "  ${BOLD}Ou bien    :${RESET}  ${GREEN}https://localhost:${PORT}/${RESET}\n"
echo ""

printf "${BOLD}══════════════════════════════════════════════════════════════${RESET}\n"
printf "${BOLD} Commandes de diagnostic${RESET}\n"
printf "${BOLD}══════════════════════════════════════════════════════════════${RESET}\n"
cat <<DIAG

  ${BOLD}1. Vérifier la chaîne avec openssl :${RESET}
  ${CYAN}openssl s_client -connect ${DOMAIN}:${PORT} -CAfile ${CA_ABS} </dev/null 2>/dev/null | head -20${RESET}
  → Doit afficher « Verify return code: 0 (ok) »

  ${BOLD}2. Tester avec curl :${RESET}
  ${CYAN}curl -v --cacert ${CA_ABS} https://${DOMAIN}:${PORT}/${RESET}
  → Doit afficher le HTML sans erreur SSL

  ${BOLD}3. Voir le certificat reçu :${RESET}
  ${CYAN}openssl s_client -connect ${DOMAIN}:${PORT} -servername ${DOMAIN} </dev/null 2>/dev/null | openssl x509 -noout -text | head -30${RESET}

DIAG
printf "${BOLD}══════════════════════════════════════════════════════════════${RESET}\n"
echo ""
info "Lancement du serveur HTTPS… (Ctrl+C pour arrêter)"
echo ""

python3 -c "${PYTHON_SERVER}" "${PORT}" "${CERT_ABS}" "${KEY_ABS}" "${CA_ABS}" "${WWW_ABS}"
