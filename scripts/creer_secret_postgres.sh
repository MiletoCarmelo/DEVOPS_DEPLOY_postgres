#!/bin/bash

# secrets from .env
POSTGRES_DB=$(grep POSTGRES_DB .env | cut -d '=' -f2)
POSTGRES_USER=$(grep POSTGRES_USER .env | cut -d '=' -f2)
POSTGRES_PASSWORD=$(grep POSTGRES_PASSWORD .env | cut -d '=' -f2)
NAMESPACE=$(grep NAMESPACE .env | cut -d '=' -f2)
NAME_SCRET=$(grep NAME_SCRET .env | cut -d '=' -f2)

# Afficher les valeurs des variables (sans le mot de passe)
echo "Variables d'environnement :"
echo "NAMESPACE=${NAMESPACE}"
echo "NAME_SCRET=${NAME_SCRET}"
echo "POSTGRES_DB=${POSTGRES_DB}"
echo "POSTGRES_USER=${POSTGRES_USER}"
echo "POSTGRES_PASSWORD=***"

# Vérifier que les variables requises sont définies
if [ -z "${POSTGRES_DB}" ] || [ -z "${POSTGRES_USER}" ] || [ -z "${POSTGRES_PASSWORD}" ]; then
    echo "❌ Erreur: Une ou plusieurs variables requises ne sont pas définies"
    echo "POSTGRES_DB=${POSTGRES_DB}"
    echo "POSTGRES_USER=${POSTGRES_USER}"
    echo "POSTGRES_PASSWORD=***" # On n'affiche pas le mot de passe pour la sécurité
    exit 1
fi

# Vérifier si le namespace existe
if ! kubectl get namespace ${NAMESPACE} >/dev/null 2>&1; then
    echo "🔄 Création du namespace ${NAMESPACE}..."
    kubectl create namespace ${NAMESPACE}
else
    echo "✅ Le namespace ${NAMESPACE} existe déjà"
fi

# Créer le secret en YAML
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${NAME_SCRET}
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  POSTGRES_DB: "${POSTGRES_DB}"
  POSTGRES_USER: "${POSTGRES_USER}"
  POSTGRES_PASSWORD: "${POSTGRES_PASSWORD}"
EOF

echo "✅ Secret ${NAME_SCRET} créé/mis à jour avec succès"

# verification contenus :
echo "🔄 Vérification du secret..."
echo "Secret YAML complet :"
kubectl get secret ${NAME_SCRET} -n ${NAMESPACE} -o yaml

echo -n "POSTGRES_DB: "
kubectl get secret ${NAME_SCRET} -n ${NAMESPACE} -o jsonpath='{.data.POSTGRES_DB}' | base64 --decode
echo

echo -n "POSTGRES_USER: "
kubectl get secret ${NAME_SCRET} -n ${NAMESPACE} -o jsonpath='{.data.POSTGRES_USER}' | base64 --decode
echo

echo -n "POSTGRES_PASSWORD: "
kubectl get secret ${NAME_SCRET} -n ${NAMESPACE} -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode
echo