#!/bin/bash

# Icônes
CHECK="✅"
ERROR="❌"
LOADING="🔄"
INFO="ℹ️ "
WARNING="⚠️ "
LOCK="🔒"
KEY="🔑"
DATABASE="🗄️ "
USER="👤"
ROCKET="🚀"
MAG="🔍"

# Charger les variables depuis .env
DAGSTER_DB=$(grep DAGSTER_DB .env | cut -d '=' -f2)
DAGSTER_USER=$(grep DAGSTER_USER .env | cut -d '=' -f2)
DAGSTER_PASSWORD=$(grep DAGSTER_PASSWORD .env | cut -d '=' -f2)
DAGSTER_NAMESPACE=$(grep NAMESPACE .env | cut -d '=' -f2)
NAME_SECRET=$(grep DAGSTER_NAME_SECRET .env | cut -d '=' -f2)

# Afficher les valeurs des variables
echo -e "${INFO} Variables d'environnement :"
echo -e "  "
echo -e "${DATABASE} NAMESPACE    : ${DAGSTER_NAMESPACE}"
echo -e "  "
echo -e "${KEY} NAME_SECRET  : ${NAME_SECRET}"
echo -e "  "
echo -e "${DATABASE} DAGSTER_DB   : ${DAGSTER_DB}"
echo -e "  "
echo -e "${USER} DAGSTER_USER : ${DAGSTER_USER}"
echo -e "  "
echo -e "${LOCK} PASSWORD     : ***"
echo -e "  "

# Vérifier que les variables requises sont définies
if [ -z "${DAGSTER_DB}" ] || [ -z "${DAGSTER_USER}" ] || [ -z "${DAGSTER_PASSWORD}" ]; then
    echo -e "${ERROR} Erreur: Une ou plusieurs variables requises ne sont pas définies"
    echo -e "DAGSTER_DB=${DAGSTER_DB}"
    echo -e "DAGSTER_USER=${DAGSTER_USER}"
    echo -e "DAGSTER_PASSWORD=***"
    exit 1
fi

# Vérifier si le namespace existe
if ! kubectl get namespace ${DAGSTER_NAMESPACE} >/dev/null 2>&1; then
    echo -e "${LOADING} Création du namespace ${DAGSTER_NAMESPACE}..."
    kubectl create namespace ${DAGSTER_NAMESPACE}
else
    echo -e "${CHECK} Le namespace ${DAGSTER_NAMESPACE} existe déjà"
fi

# Créer le secret en YAML
echo -e "${LOADING} Création du secret..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${NAME_SECRET}
  namespace: ${DAGSTER_NAMESPACE}
type: Opaque
stringData:
  POSTGRES_DB: "${DAGSTER_DB}"
  POSTGRES_USER: "${DAGSTER_USER}"
  POSTGRES_PASSWORD: "${DAGSTER_PASSWORD}"
EOF
echo -e "${CHECK} Secret ${NAME_SECRET} créé/mis à jour avec succès"

# Vérification du contenu
echo -e "\n${MAG} Vérification du secret..."
echo -e "${INFO} Secret YAML complet :"
kubectl get secret ${NAME_SECRET} -n ${DAGSTER_NAMESPACE} -o yaml

echo -e "\n${INFO} Contenu décodé du secret :"
echo -e "${DATABASE} POSTGRES_DB: $(kubectl get secret ${NAME_SECRET} -n ${DAGSTER_NAMESPACE} -o jsonpath='{.data.POSTGRES_DB}' | base64 --decode)"
echo -e "${USER} POSTGRES_USER: $(kubectl get secret ${NAME_SECRET} -n ${DAGSTER_NAMESPACE} -o jsonpath='{.data.POSTGRES_USER}' | base64 --decode)"
echo -e "${LOCK} POSTGRES_PASSWORD: $(kubectl get secret ${NAME_SECRET} -n ${DAGSTER_NAMESPACE} -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode)"

echo -e "\n${ROCKET} ${CHECK} Secret créé et vérifié avec succès !"