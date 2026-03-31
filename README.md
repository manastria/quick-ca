# Labo PKI : Test de certificat dans Firefox

Ce projet permet de valider l'importation d'une Autorité de Certification (AC) locale dans Firefox et la vérification d'un certificat serveur signé par cette AC.

## 📂 Ressources disponibles

- **`pki-web.lab.local/`** : Répertoire contenant les artefacts de la PKI.
  - `ca.crt` : Le certificat de l'AC (à importer dans le navigateur).
  - `server.crt` / `server.key` : Le certificat du serveur et sa clé privée.
- **`certificat.txt`** : Résumé des caractéristiques du certificat généré (domaines SAN, dates de validité, empreintes).
- **`server-ca.sh`** : Script de lancement du serveur HTTPS de test.
- **`diagnostics.md`** : Guide détaillé de dépannage en cas d'erreur TLS dans Firefox.

## 🚀 Procédure de test

### 1. Configuration locale (DNS)
Le certificat est configuré pour le domaine `web.lab.local`. Ajoutez-le à votre fichier hosts pour permettre la résolution locale :

```bash
echo '127.0.0.1   web.lab.local' | sudo tee -a /etc/hosts
```

### 2. Importation de l'AC
Pour que Firefox fasse confiance au serveur, vous devez lui fournir le certificat de l'AC :
1. Dans Firefox, allez dans **Paramètres** > **Vie privée et sécurité**.
2. Section **Certificats**, cliquez sur **Afficher les certificats**.
3. Dans l'onglet **Autorités**, cliquez sur **Importer**.
4. Sélectionnez le fichier `pki-web.lab.local/ca.crt`.
5. **Important** : Cochez la case *"Confirmer cette AC pour identifier des sites web"*.

### 3. Lancement du serveur
Lancez le serveur de test qui utilisera les certificats du répertoire `./pki-web.lab.local` :

```bash
./server-ca.sh ./pki-web.lab.local
```

### 4. Validation
Accédez à l'URL suivante dans Firefox :
👉 **[https://web.lab.local:8443](https://web.lab.local:8443)**

La page doit s'afficher avec un **cadenas** et sans aucun avertissement de sécurité.

## 🛠️ Dépannage
Si vous rencontrez une erreur (ex: `SEC_ERROR_UNKNOWN_ISSUER`), consultez la fiche d'aide :
[Guide de diagnostic et dépannage](./diagnostics.md)
