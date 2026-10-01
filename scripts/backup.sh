#!/usr/bin/env bash
# Sauvegarde de la base MySQL et du volume de données Tuleap.
# Usage : ./scripts/backup.sh [dossier_destination]
set -euo pipefail

DEST="${1:-/mnt/backup_syno4/mes_images/tuleap}"
DATA_PARENT="${TULEAP_DATA_PARENT:-/volume2/docker/tuleap}"
STAMP="$(date +%Y%m%d)"

mkdir -p "$DEST"

# Le mot de passe root est lu dans l'environnement du conteneur : rien en clair ici
docker exec TULEAP-DB sh -c 'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --all-databases --single-transaction' \
  > "$DEST/tuleap-db-$STAMP.sql"

tar -czf "$DEST/tuleap-data-$STAMP.tar.gz" -C "$DATA_PARENT" data

echo "Sauvegarde terminée dans $DEST"
