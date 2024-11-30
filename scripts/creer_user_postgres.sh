#!/bin/bash

# Couleurs et icônes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
CHECK_MARK="${GREEN}✓${NC}"
CROSS_MARK="${RED}✗${NC}"
ARROW="${BLUE}➜${NC}"
INFO="${BLUE}ℹ${NC}"
WARN="${YELLOW}⚠${NC}"

# Fonction pour gérer les erreurs
handle_error() {
    echo -e "${CROSS_MARK} ${RED}Erreur: $1${NC}"
    exit 1
}

# Fonction pour afficher les étapes
print_step() {
    echo -e "\n${ARROW} ${BLUE}Step $1:${NC} $2"
}

# Step 1: Chargement et vérification de la configuration
print_step "1" "Chargement de la configuration..."

# Créer le fichier .env s'il n'existe pas
if [ ! -f .env ]; then
    echo -e "${INFO} Création d'un nouveau fichier .env..."
    touch .env
fi

# Charger le fichier .env existant
. ./.env

# Fonction pour vérifier et demander une variable
check_and_ask_variable() {
    local var_name=$1
    local description=$2
    
    if [ -z "${!var_name}" ]; then
        echo -e "${INFO} $description :"
        read value
        echo "${var_name}=${value}" >> .env
        export "${var_name}=${value}"
    fi
}

# Fonction pour vérifier et demander une variable
check_and_ask_variable_pod() {
    local var_name=$1
    local description=$2
    local NAMESPACE=$3
    
    if [ -z "${!var_name}" ]; then
        echo -e "${INFO} Pods disponibles dans le namespace ${NAMESPACE} :"
        kubectl get pods -n "$NAMESPACE" || handle_error "Impossible de lister les pods"
        echo -e "${INFO} $description :"
        read value
        echo "${var_name}=${value}" >> .env
        export "${var_name}=${value}"
    fi
}

# Vérifier toutes les variables nécessaires
check_and_ask_variable "NAMESPACE" "Entrez le namespace"
check_and_ask_variable "POSTGRES_DB_GRANT" "Entrez le nom de la base de données admin"
check_and_ask_variable "POSTGRES_USER_GRANT" "Entrez le nom de l'utilisateur admin"
check_and_ask_variable "POSTGRES_PASSWORD_GRANT" "Entrez le mot de passe admin"
check_and_ask_variable "DAGSTER_DB" "Entrez le nom de la nouvelle base de données"
check_and_ask_variable "DAGSTER_USER" "Entrez le nom du nouvel utilisateur"
check_and_ask_variable "DAGSTER_PASSWORD" "Entrez le mot de passe du nouvel utilisateur"

echo -e "${CHECK_MARK} Configuration chargée avec succès"

# Step 2: Vérification du namespace
print_step "2" "Vérification du namespace..."
echo -e "${INFO} Utilisation du namespace: ${NAMESPACE}"

if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
    handle_error "Le namespace '$NAMESPACE' n'existe pas."
fi
echo -e "${CHECK_MARK} Namespace vérifié avec succès"

# Step 3: Sélection du pod
print_step "3" "Sélection du pod..."
check_and_ask_variable_pod "POSTGRES_POD" " Entrez le nom du pod à utiliser :" "${NAMESPACE}"


# Vérifier si le pod est prêt
POD_STATUS=$(kubectl get pod "$POSTGRES_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null) || handle_error "Le pod '$POSTGRES_POD' n'existe pas"
if [ "$POD_STATUS" != "Running" ]; then
    handle_error "Le pod '$POSTGRES_POD' n'est pas en état 'Running' (état actuel: $POD_STATUS)"
fi
echo -e "${CHECK_MARK} Pod vérifié avec succès"

# Step 4: Affichage et confirmation de la configuration
print_step "4" "Vérification de la configuration..."
echo -e "${INFO} Configuration détectée :"
echo -e "  ${BLUE}•${NC} Namespace          : $NAMESPACE"
echo -e "  ${BLUE}•${NC} Pod               : $POSTGRES_POD"
echo -e "  ${BLUE}•${NC} Admin User        : $POSTGRES_USER_GRANT"
echo -e "  ${BLUE}•${NC} Admin Database    : $POSTGRES_DB_GRANT"
echo -e "  ${BLUE}•${NC} Nouveau User      : $DAGSTER_USER"
echo -e "  ${BLUE}•${NC} Nouvelle DB       : $DAGSTER_DB"

echo -e "\n${WARN} Voulez-vous continuer avec cette configuration ? (yes/no)"
read response
case "$response" in
    [Yy][Ee][Ss]|[Yy])
        echo -e "${CHECK_MARK} Configuration confirmée"
        ;;
    *)
        echo -e "${INFO} Opération annulée par l'utilisateur."
        exit 0
        ;;
esac

# Step 5: Création du fichier SQL
print_step "5" "Création du fichier SQL..."
cat << EOF > /tmp/init_dagster_db.sql || handle_error "Impossible de créer le fichier SQL"
-- Créer un nouvel utilisateur
CREATE USER ${DAGSTER_USER} WITH PASSWORD '${DAGSTER_PASSWORD}';

-- Créer une nouvelle base de données
CREATE DATABASE ${DAGSTER_DB} WITH OWNER ${DAGSTER_USER};

-- Se connecter à la nouvelle base de données
\c ${DAGSTER_DB}

-- Donner les permissions nécessaires
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DAGSTER_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DAGSTER_USER};
GRANT ALL PRIVILEGES ON SCHEMA public TO ${DAGSTER_USER};

-- Pour permettre à l'utilisateur de créer de nouvelles tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO ${DAGSTER_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO ${DAGSTER_USER};
EOF
echo -e "${CHECK_MARK} Fichier SQL créé avec succès"

# Step 6: Copie du fichier SQL vers le pod
print_step "6" "Copie du fichier SQL vers le pod..."
kubectl cp /tmp/init_dagster_db.sql "${NAMESPACE}/${POSTGRES_POD}:/tmp/init_dagster_db.sql" || handle_error "Impossible de copier le fichier SQL dans le pod"
echo -e "${CHECK_MARK} Fichier SQL copié avec succès"

# Step 7: Exécution du script SQL
print_step "7" "Exécution du script SQL..."
kubectl exec -it "${POSTGRES_POD}" -n "${NAMESPACE}" -- \
    psql -U "${POSTGRES_USER_GRANT}" -d "${POSTGRES_DB_GRANT}" -f /tmp/init_dagster_db.sql || handle_error "Erreur lors de l'exécution du script SQL"
echo -e "${CHECK_MARK} Script SQL exécuté avec succès"

# Step 8: Nettoyage
print_step "8" "Nettoyage..."
rm /tmp/init_dagster_db.sql
kubectl exec -it "${POSTGRES_POD}" -n "${NAMESPACE}" -- rm /tmp/init_dagster_db.sql
echo -e "${CHECK_MARK} Nettoyage effectué avec succès"

# Step 9: Test de connexion
print_step "9" "Test de connexion avec le nouvel utilisateur..."
TEST_QUERY="SELECT current_database(), current_user, version();"
echo -e "${INFO} Tentative de connexion à la base ${DAGSTER_DB} avec l'utilisateur ${DAGSTER_USER}..."

RESULT=$(kubectl exec "${POSTGRES_POD}" -n "${NAMESPACE}" -- \
    env PGPASSWORD="${DAGSTER_PASSWORD}" psql -U "${DAGSTER_USER}" -d "${DAGSTER_DB}" -c "${TEST_QUERY}" 2>&1) || {
    echo -e "${CROSS_MARK} ${RED}La connexion a échoué${NC}"
    echo -e "${INFO} Détails de l'erreur :\n$RESULT"
    handle_error "Impossible de se connecter avec le nouvel utilisateur"
}

echo -e "${CHECK_MARK} ${GREEN}Connexion réussie !${NC}"
echo -e "${INFO} Détails de la connexion :\n$RESULT"

echo -e "\n${CHECK_MARK} ${GREEN}Configuration terminée avec succès !${NC}"
echo -e "${INFO} Récapitulatif :"
echo -e "  ${BLUE}•${NC} Base de données : ${DAGSTER_DB}"
echo -e "  ${BLUE}•${NC} Utilisateur     : ${DAGSTER_USER}"
echo -e "  ${BLUE}•${NC} Mot de passe    : ${DAGSTER_PASSWORD}"
echo -e "${WARN} Conservez ces informations en lieu sûr."