# Diagnostic TLS — Quand Firefox refuse votre certificat

Vous avez configuré votre serveur HTTPS, importé votre AC dans Firefox, mais quelque chose ne fonctionne pas. Cette fiche vous guide pas à pas pour **identifier et corriger le problème**.

La méthode est toujours la même : on part du symptôme visible dans Firefox, puis on remonte la chaîne de confiance maillon par maillon avec `openssl` et `certutil`.

> **Convention** : dans toute la fiche, remplacez `web.lab.local` par votre domaine et `8443` par votre port.

---

## 1. Identifier le symptôme dans Firefox

Quand Firefox affiche un avertissement de sécurité, le message d'erreur vous oriente déjà vers la cause. Ouvrez la page `https://web.lab.local:8443/` et notez le **code d'erreur** affiché.

| Code Firefox | Signification | Section à consulter |
|---|---|---|
| `SEC_ERROR_UNKNOWN_ISSUER` | Firefox ne reconnaît pas l'AC qui a signé le certificat | §2, §3, §4 |
| `SSL_ERROR_BAD_CERT_DOMAIN` | Le domaine dans l'URL ne correspond pas au certificat | §5 |
| `SEC_ERROR_EXPIRED_CERTIFICATE` | Le certificat ou l'AC a expiré | §6 |
| `MOZILLA_PKIX_ERROR_CA_CERT_USED_AS_END_ENTITY` | Le certificat serveur est en réalité un certificat CA | §7 |
| `SEC_ERROR_INADEQUATE_KEY_USAGE` | Les extensions du certificat sont incorrectes | §7 |
| Connexion impossible (pas d'erreur TLS) | Le serveur n'écoute pas ou le domaine ne résout pas | §8 |

> **Astuce** : cliquez sur « Avancé » dans la page d'avertissement pour voir le code d'erreur complet et les détails du certificat que Firefox a reçu.

---

## 2. Vérifier que l'AC est importée dans le bon magasin

C'est l'erreur **la plus fréquente**. Firefox possède deux magasins de certificats :

- **Autorités** : les AC de confiance (c'est ici qu'il faut importer `ca.crt`)
- **Vos certificats** : les certificats personnels du client (ce n'est **pas** ici)

### Vérification visuelle

Dans Firefox : Paramètres → Vie privée et sécurité → Certificats → Afficher les certificats → onglet **Autorités**.

Cherchez le nom de votre AC (par exemple « Labo BTS SIO »). Si elle n'apparaît pas dans cet onglet mais apparaît dans « Vos certificats », vous l'avez importée au mauvais endroit.

### Vérification en ligne de commande

Le profil Firefox n'a pas un nom fixe — il contient un identifiant aléatoire (par exemple `12j1entr.default`). Commencez par le repérer :

```bash
# Trouver le répertoire du profil qui contient le magasin de certificats
find ~/ -name "cert9.db" -path "*/firefox/*" 2>/dev/null
```

Le résultat vous donne le chemin exact. Par exemple :

- **Firefox classique (apt/deb)** : `~/.mozilla/firefox/xxxxxxxx.default-release/cert9.db`
- **Firefox Snap** : `~/snap/firefox/common/.mozilla/firefox/xxxxxxxx.default/cert9.db`

Stockez ce chemin dans une variable pour la suite (en retirant `/cert9.db` de la fin) :

```bash
# Adaptez le chemin affiché par la commande find ci-dessus
FF_PROFILE="$(find ~/ -name cert9.db -path '*/firefox/*' -printf '%h' -quit 2>/dev/null)"
echo "Profil trouvé : ${FF_PROFILE}"
```

Ensuite, listez les certificats de confiance :

```bash
certutil -L -d "sql:${FF_PROFILE}"
```

Vous devez trouver une ligne semblable à :

```
AC Labo BTS SIO                                      C,,
```

Le `C,,` signifie « AC de confiance pour les sites web ». Si vous voyez `,,` ou `P,,` ou autre chose, la confiance n'est pas correctement attribuée.

### Corriger le problème

Supprimez l'entrée incorrecte et réimportez proprement :

```bash
# Supprimer l'ancienne entrée
certutil -D -d "sql:${FF_PROFILE}" -n "AC Labo BTS SIO"

# Réimporter avec le bon niveau de confiance
certutil -A -d "sql:${FF_PROFILE}" \
    -n "AC Labo BTS SIO" -t "C,," -i ca.crt
```

Après toute modification avec `certutil`, **redémarrez Firefox** complètement (fermez toutes les fenêtres, pas juste l'onglet).

---

## 3. Vérifier qu'on a importé la bonne AC

Autre erreur classique : vous avez généré la PKI plusieurs fois et le `ca.crt` importé dans Firefox ne correspond plus à celui qui a signé votre certificat serveur.

### Test décisif

```bash
openssl verify -CAfile ca.crt server.crt
```

Résultat attendu :

```
server.crt: OK
```

Si vous obtenez une erreur du type `unable to get local issuer certificate` ou `certificate signature failure`, cela signifie que `server.crt` n'a **pas** été signé par ce `ca.crt`. Vous avez probablement un ancien fichier qui traîne.

### Comparer les empreintes

Pour confirmer, comparez l'empreinte de l'AC qui a signé le certificat serveur avec celle du fichier `ca.crt` :

```bash
# Empreinte de ca.crt (le fichier que vous avez)
openssl x509 -in ca.crt -noout -fingerprint -sha256

# Empreinte de l'AC qui a réellement signé server.crt
# (visible dans le champ "Issuer" et vérifiable par la signature)
openssl x509 -in server.crt -noout -issuer
openssl x509 -in ca.crt -noout -subject
```

Les champs `issuer` du certificat serveur et `subject` de `ca.crt` doivent être **strictement identiques**.

### Comparer avec ce qui est dans Firefox

```bash
# Exporter le certificat CA tel que Firefox le connaît
certutil -L -d "sql:${FF_PROFILE}" \
    -n "AC Labo BTS SIO" -a > /tmp/ca-firefox.crt

# Comparer les empreintes
openssl x509 -in ca.crt -noout -fingerprint -sha256
openssl x509 -in /tmp/ca-firefox.crt -noout -fingerprint -sha256
```

Si les deux empreintes diffèrent, Firefox a une ancienne version de l'AC. Supprimez-la et réimportez la bonne (voir §2).

---

## 4. Vérifier la chaîne côté serveur

Même si Firefox a la bonne AC, le serveur doit envoyer le bon certificat. Connectez-vous au serveur et examinez ce qu'il envoie réellement :

```bash
openssl s_client -connect web.lab.local:8443 -servername web.lab.local </dev/null 2>/dev/null
```

### Ce qu'il faut regarder dans la sortie

**La chaîne de certificats** (en haut de la sortie) :

```
Certificate chain
 0 s:C = FR, ST = Hauts-de-France, ..., CN = web.lab.local
   i:C = FR, ST = Hauts-de-France, ..., CN = AC Labo BTS SIO
```

- La ligne `s:` (*subject*) est l'identité du certificat serveur. Le `CN` doit correspondre à votre domaine.
- La ligne `i:` (*issuer*) est l'AC qui l'a signé. Elle doit correspondre à l'AC importée dans Firefox.

**Le code de vérification** (en bas de la sortie) :

```
Verify return code: 0 (ok)
```

Si le code n'est pas `0`, consultez le tableau suivant :

| Code | Message | Cause probable |
|---|---|---|
| `2` | `unable to get issuer certificate` | L'AC n'est pas trouvée, chaîne incomplète |
| `10` | `certificate has expired` | Certificat ou AC expiré (voir §6) |
| `18` | `self-signed certificate` | Le serveur envoie un certificat auto-signé au lieu d'un certificat signé par l'AC |
| `19` | `self-signed certificate in chain` | Le certificat CA est auto-signé (normal) mais n'est pas de confiance |
| `20` | `unable to get local issuer certificate` | Le fichier CA fourni ne correspond pas à celui qui a signé le certificat |
| `21` | `unable to verify the first certificate` | Le serveur n'envoie pas la chaîne complète |

### Test avec votre CA explicitement

```bash
openssl s_client -connect web.lab.local:8443 -CAfile ca.crt </dev/null 2>/dev/null | tail -5
```

Si cette commande retourne `Verify return code: 0 (ok)` mais que Firefox refuse quand même, le problème est dans Firefox (retournez au §2 et §3).

---

## 5. Vérifier la correspondance domaine / certificat

Firefox vérifie que le domaine dans la barre d'adresse correspond au champ **SAN** (*Subject Alternative Name*) du certificat. Le champ CN seul ne suffit plus dans les navigateurs modernes.

### Voir les SAN du certificat

```bash
openssl x509 -in server.crt -noout -ext subjectAltName
```

Résultat attendu :

```
X509v3 Subject Alternative Name:
    DNS:web.lab.local, DNS:www.web.lab.local, IP Address:127.0.0.1
```

### Causes d'erreur

- Vous accédez à `https://localhost:8443/` mais le SAN ne contient pas `DNS:localhost` (il contient `IP:127.0.0.1`, ce n'est pas la même chose)
- Vous accédez à `https://192.168.1.10:8443/` mais le SAN ne contient pas `IP:192.168.1.10`
- Vous accédez à `https://www.web.lab.local:8443/` mais le SAN ne contient que `DNS:web.lab.local` sans le `www`

**Règle** : le domaine ou l'IP dans l'URL doit apparaître **exactement** dans les SAN du certificat.

### Corriger

Modifiez les variables `DOMAIN` et `EXTRA_SANS` dans `quick-ca.sh` et régénérez toute la PKI. Il n'est pas possible de modifier les SAN d'un certificat déjà signé.

---

## 6. Vérifier les dates de validité

```bash
openssl x509 -in server.crt -noout -dates
```

Résultat :

```
notBefore=Mar 27 13:38:58 2026 GMT
notAfter=Jun 29 13:38:58 2028 GMT
```

Vérifiez aussi l'AC :

```bash
openssl x509 -in ca.crt -noout -dates
```

Comparez avec la date actuelle :

```bash
date -u
```

Si le certificat n'est pas encore valide (`notBefore` dans le futur), c'est souvent un problème d'horloge sur la VM. Corrigez avec :

```bash
sudo timedatectl set-ntp true
```

---

## 7. Vérifier les extensions du certificat

Un certificat serveur doit contenir des extensions précises. Si elles sont absentes ou incorrectes, Firefox le rejettera même si la chaîne de confiance est correcte.

```bash
openssl x509 -in server.crt -noout -text | grep -A2 -E "Basic Constraints|Key Usage|Extended Key Usage"
```

### Ce qui est attendu pour un certificat serveur

```
X509v3 Basic Constraints: critical
    CA:FALSE
X509v3 Key Usage: critical
    Digital Signature, Key Encipherment
X509v3 Extended Key Usage:
    TLS Web Server Authentication
```

### Erreurs courantes

| Problème | Symptôme |
|---|---|
| `CA:TRUE` au lieu de `CA:FALSE` | Firefox refuse d'utiliser un certificat CA comme certificat serveur |
| `Extended Key Usage` absent | Certains navigateurs le tolèrent, d'autres non |
| `serverAuth` absent de `Extended Key Usage` | Le certificat n'est pas autorisé pour HTTPS |
| `Key Usage` ne contient pas `digitalSignature` | Le handshake TLS échouera |

Si les extensions sont incorrectes, il faut régénérer le certificat. Vérifiez la section `[ v3_server ]` dans le script `quick-ca.sh`.

---

## 8. Vérifier la connectivité de base

Avant tout diagnostic TLS, assurez-vous que le serveur est joignable.

### Le domaine résout-il vers la bonne IP ?

```bash
getent hosts web.lab.local
```

Si aucun résultat, le domaine n'est pas dans `/etc/hosts` et n'est pas résolu par le DNS. Ajoutez-le :

```bash
echo '127.0.0.1   web.lab.local' | sudo tee -a /etc/hosts
```

### Le serveur écoute-t-il ?

```bash
ss -tlnp | grep 8443
```

Vous devez voir une ligne avec `LISTEN` sur le port attendu. Si rien n'apparaît, le serveur n'est pas lancé ou écoute sur un autre port.

### Le pare-feu bloque-t-il ?

```bash
sudo ufw status
```

Si `ufw` est actif, vérifiez que le port est autorisé :

```bash
sudo ufw allow 8443/tcp
```

---

## 9. Méthode systématique — résumé

Quand rien ne marche, suivez cette liste dans l'ordre. Chaque étape élimine une cause possible.

Commencez par stocker le chemin du profil Firefox (voir §2 pour l'explication) :

```bash
FF_PROFILE="$(find ~/ -name cert9.db -path '*/firefox/*' -printf '%h' -quit 2>/dev/null)"
```

**Étape 1 — Le serveur est-il joignable ?**

```bash
ss -tlnp | grep 8443
getent hosts web.lab.local
```

**Étape 2 — Le serveur envoie-t-il le bon certificat ?**

```bash
openssl s_client -connect web.lab.local:8443 </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -ext subjectAltName
```

**Étape 3 — La chaîne est-elle valide avec votre CA ?**

```bash
openssl verify -CAfile ca.crt server.crt
```

**Étape 4 — Firefox a-t-il la même AC ?**

```bash
certutil -L -d "sql:${FF_PROFILE}" -n "AC Labo BTS SIO" -a \
    | openssl x509 -noout -fingerprint -sha256

openssl x509 -in ca.crt -noout -fingerprint -sha256
```

Les deux empreintes doivent être identiques.

**Étape 5 — La confiance est-elle correcte ?**

```bash
certutil -L -d "sql:${FF_PROFILE}" | grep "AC Labo"
```

La ligne doit se terminer par `C,,`.

Si toutes ces étapes passent et que Firefox refuse toujours, fermez **toutes** les fenêtres Firefox et relancez-le. Firefox met en cache les décisions de sécurité et ne relit pas le magasin de certificats en temps réel.