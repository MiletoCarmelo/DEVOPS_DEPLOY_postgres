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
POSTGRES_DB=$(grep POSTGRES_DB_GRANT .env | cut -d '=' -f2)
POSTGRES_USER=$(grep POSTGRES_USER_GRANT .env | cut -d '=' -f2)
POSTGRES_PASSWORD=$(grep POSTGRES_PASSWORD_GRANT .env | cut -d '=' -f2)
POSTGRES_NAMESPACE=$(grep NAMESPACE .env | cut -d '=' -f2)
NAME_SECRET=$(grep POSTGRES_NAME_SECRET_GRANT .env | cut -d '=' -f2)

# Afficher les valeurs des variables
echo -e "${INFO} Variables d'environnement :"
echo -e "  "
echo -e "${DATABASE} NAMESPACE    : ${POSTGRES_NAMESPACE}"
echo -e "  "
echo -e "${KEY} NAME_SECRET  : ${NAME_SECRET}"
echo -e "  "
echo -e "${DATABASE} POSTGRES_DB   : ${POSTGRES_DB}"
echo -e "  "
echo -e "${USER} POSTGRES_USER : ${POSTGRES_USER}"
echo -e "  "
echo -e "${LOCK} PASSWORD     : ***"
echo -e "  "

# Vérifier que les variables requises sont définies
if [ -z "${POSTGRES_DB}" ] || [ -z "${POSTGRES_USER}" ] || [ -z "${POSTGRES_PASSWORD}" ]; then
    echo -e "${ERROR} Erreur: Une ou plusieurs variables requises ne sont pas définies"
    echo -e "POSTGRES_DB=${POSTGRES_DB}"
    echo -e "POSTGRES_USER=${POSTGRES_USER}"
    echo -e "POSTGRES_PASSWORD=***"
    exit 1
fi

# Vérifier si le namespace existe
if ! kubectl get namespace ${POSTGRES_NAMESPACE} >/dev/null 2>&1; then
    echo -e "${LOADING} Création du namespace ${POSTGRES_NAMESPACE}..."
    kubectl create namespace ${POSTGRES_NAMESPACE}
else
    echo -e "${CHECK} Le namespace ${POSTGRES_NAMESPACE} existe déjà"
fi

# Créer le secret en YAML
echo -e "${LOADING} Création du secret..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${NAME_SECRET}
  namespace: ${POSTGRES_NAMESPACE}
type: Opaque
stringData:
  POSTGRES_DB: "${POSTGRES_DB}"
  POSTGRES_USER: "${POSTGRES_USER}"
  POSTGRES_PASSWORD: "${POSTGRES_PASSWORD}"
EOF
echo -e "${CHECK} Secret ${NAME_SECRET} créé/mis à jour avec succès"

# Vérification du contenu
echo -e "\n${MAG} Vérification du secret..."
echo -e "${INFO} Secret YAML complet :"
kubectl get secret ${NAME_SECRET} -n ${POSTGRES_NAMESPACE} -o yaml

echo -e "\n${INFO} Contenu décodé du secret :"
echo -e " => ${DATABASE} POSTGRES_DB: $(kubectl get secret ${NAME_SECRET} -n ${POSTGRES_NAMESPACE} -o jsonpath='{.data.POSTGRES_DB}' | base64 --decode)"
echo -e " => ${USER} POSTGRES_USER: $(kubectl get secret ${NAME_SECRET} -n ${POSTGRES_NAMESPACE} -o jsonpath='{.data.POSTGRES_USER}' | base64 --decode)"
echo -e " => ${LOCK} POSTGRES_PASSWORD: $(kubectl get secret ${NAME_SECRET} -n ${POSTGRES_NAMESPACE} -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode)"

echo -e "\n${ROCKET} ${CHECK} Secret créé et vérifié avec succès !"