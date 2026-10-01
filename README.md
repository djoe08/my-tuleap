# Tuleap (Docker + Portainer + Nginx Proxy Manager)

Environnement cible : hôte Docker (`debian13-docker`), réseau `Docker_Net` existant, données persistantes sous `/volume2/docker/tuleap/`, stack géré via Portainer.

Architecture : 2 services, images officielles :
- `tuleap-db` : MySQL 8.4 (base applicative) ;
- `tuleap` : image officielle `tuleap/tuleap-community-edition`, tout-en-un (web, Git, SVN, tracker, forge de projet).

Aucun build : les images sont tirées depuis Docker Hub.

## Contenu du dépôt

| Fichier | Rôle |
|---|---|
| `docker-compose.yml` | Stack à coller dans Portainer (secrets via variables) |
| `.env.example` | Modèle des variables à renseigner |
| `scripts/backup.sh` | Sauvegarde base + volume de données |

> ⚠️ Ce dépôt est public : les mots de passe ne sont **jamais** committés. Ils vivent dans `.env` (ignoré par Git) ou dans les variables d'environnement du stack Portainer.

## Particularité importante : Tuleap termine lui-même le TLS

Le conteneur Tuleap **ne parle qu'en HTTPS**, avec un certificat auto-signé généré au premier démarrage. Deux façons de faire cohabiter ça avec NPM :

- **Recommandée ici** : NPM en frontal avec `Forward Scheme: https` vers le conteneur (NPM ne vérifie pas le certificat du backend par défaut). NPM présente ensuite un vrai certificat public aux clients.
- **Alternative documentée par Tuleap** : remplacer le certificat auto-signé par le tien dans le volume de données, et exposer Tuleap sans passer par NPM.

Le port **22** (Git/SVN par SSH) est publié sur l'hôte sur un port dédié, **2220**, pour éviter tout conflit avec le SSH d'administration ou Warpgate (déjà sur 2222).

Contrainte de mot de passe imposée par Tuleap : au moins 20 caractères, **lettres et chiffres uniquement**. Pour en générer un :

```bash
tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24; echo
```

---

## 1. Créer les dossiers

```bash
mkdir -p /volume2/docker/tuleap/data
mkdir -p /volume2/docker/tuleap/db
```

## 2. Déployer le stack via Portainer

1. Portainer → Stacks → Add stack → Web editor : coller le contenu de [`docker-compose.yml`](docker-compose.yml).
   (Alternative : option *Repository* pointant sur ce dépôt.)
2. Section **Environment variables** : renseigner au minimum `MYSQL_ROOT_PASSWORD`, `TULEAP_SYS_DBPASSWD`, `SITE_ADMINISTRATOR_PASSWORD` (ou *Load variables from .env file* avec un `.env` dérivé de [`.env.example`](.env.example)).
3. "Deploy the stack".

En ligne de commande, l'équivalent :

```bash
cp .env.example .env   # puis éditer les mots de passe
docker compose up -d
```

Note : Tuleap crée lui-même sa base et son utilisateur applicatif (`tuleapadm`) au premier démarrage à partir de `DB_ADMIN_USER`/`DB_ADMIN_PASSWORD` — pas besoin de `MYSQL_DATABASE`/`MYSQL_USER` sur le service `tuleap-db`.

## 3. Suivre la progression de l'installation

```bash
docker logs -f TULEAP
```

L'installation initiale peut prendre plusieurs minutes (génération de certificat, création du schéma, configuration de Git, SVN, cron, Postfix...). C'est prêt quand les logs mentionnent le nom de domaine configuré et le démarrage de Supervisord sans erreur.

## 4. Configurer Nginx Proxy Manager

Dans NPM → Proxy Hosts → Add Proxy Host :

| Champ | Valeur |
|---|---|
| Domain Names | `tuleap.jo.priv` |
| Scheme | `https` |
| Forward Hostname/IP | `TULEAP` |
| Forward Port | `443` |
| SSL | Let's Encrypt ou certificat existant, activé sur ce Proxy Host |

## 5. Premier accès

- Interface : `https://tuleap.jo.priv`
- Compte admin : `admin` / valeur de `SITE_ADMINISTRATOR_PASSWORD`
- Accès Git/SVN par SSH : `ssh -p 2220 <utilisateur>@<ip-hôte>`

## 6. Configurer l'envoi d'e-mails (recommandé)

Sans relais SMTP, Tuleap utilise `sendmail` local, généralement inutilisable hors du conteneur. Décommenter dans `docker-compose.yml` (service `tuleap`) et renseigner les variables correspondantes :

```yaml
      - TULEAP_EMAIL_TRANSPORT=smtp
      - TULEAP_EMAIL_RELAYHOST=${TULEAP_EMAIL_RELAYHOST}
      - TULEAP_SYS_EMAIL_ADMIN=${TULEAP_SYS_EMAIL_ADMIN}
```

---

## Sauvegarde

```bash
./scripts/backup.sh                       # vers /mnt/backup_syno4/mes_images/tuleap
./scripts/backup.sh /autre/destination    # destination personnalisée
```

Le script fait un `mysqldump --all-databases --single-transaction` (mot de passe lu dans l'environnement du conteneur) et une archive du dossier `data`.

Le dossier `/data` contient aussi les dépôts Git/SVN des projets : il peut devenir volumineux, à surveiller (disque système de l'hôte déjà à 82 %).

## Points d'attention

- **Permissions du volume MySQL** : si `TULEAP-DB` échoue avec « Operation not permitted » (même symptôme que Postgres pour AppFlowy), la cause côté hôte n'a jamais été identifiée. Récupérer `docker logs TULEAP-DB` et `docker info | grep -i userns`.
- **Nom de service MySQL unique** : `tuleap-db` est volontairement préfixé (cf. conflit de nom rencontré avec GLPI sur `Docker_Net`).
- **Community vs Enterprise** : cette procédure utilise la Community Edition (gratuite). L'Enterprise nécessite un abonnement et un registre privé (`docker.tuleap.org`).
- **Base de données en conteneur** : Enalean déconseille de faire tourner la base de production en conteneur — acceptable en home lab, à garder en tête si l'usage devient critique.
