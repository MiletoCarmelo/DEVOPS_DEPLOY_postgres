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

# Function to check if namespace exists
check_namespace() {
    local namespace=$1
    echo "🔍 Vérifification du namespace: $namespace"
    
    # Get all namespaces
    echo "📋 Liste des namespaces disponibles:"
    kubectl get namespaces -o custom-columns=NAME:.metadata.name --no-headers

    # Check if namespace exists
    if ! kubectl get namespace "$namespace" &> /dev/null; then
        echo "⚠️ Le namespace '$namespace' n'existe pas."
        
        # Ask user if they want to use a different namespace
        echo
        read -p "👉 Voulez-vous utiliser un namespace différent? (o/n): " change_ns
        
        if [[ "$change_ns" =~ ^[Oo]$ ]]; then
            echo
            read -p "📝 Entrez le nom du namespace: " new_namespace
            
            # Check if new namespace exists
            if ! kubectl get namespace "$new_namespace" &> /dev/null; then
                echo "⚠️ Le namespace '$new_namespace' n'existe pas non plus."
                echo "📦 Création du namespace '$new_namespace'..."
                
                if kubectl create namespace "$new_namespace"; then
                    echo "✅ Namespace '$new_namespace' créé avec succès!"
                    NAMESPACE="$new_namespace"
                    return 0
                else
                    echo "❌ Erreur lors de la création du namespace."
                    return 1
                fi
            else
                NAMESPACE="$new_namespace"
                return 0
            fi
        else
            echo "📦 Création du namespace '$namespace'..."
            if kubectl create namespace "$namespace"; then
                echo "✅ Namespace '$namespace' créé avec succès!"
                return 0
            else
                echo "❌ Erreur lors de la création du namespace."
                return 1
            fi
        fi
    fi
    
    echo "✅ Namespace '$namespace' existe."
    return 0
}


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

# Function to update env file
update_env_value() {
    local key=$1
    local value=$2
    local env_file=".env"
    
    # Si la clé existe déjà, la remplacer
    if grep -q "^${key}=" "$env_file"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
    else
        # Sinon, l'ajouter
        echo "${key}=${value}" >> "$env_file"
    fi
}

# Fonction améliorée pour vérifier et demander un pod
check_and_ask_variable_pod() {
    local var_name=$1
    local description=$2
    local NAMESPACE=$3
    
    echo -e "${INFO} Pod demandé: ${!var_name}"
    
    # Obtenir la liste des pods dans le namespace
    echo -e "${INFO} Liste des pods disponibles dans le namespace ${NAMESPACE}:"
    local pods_list
    pods_list=$(kubectl get pods -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${CROSS_MARK} Erreur lors de la récupération des pods"
        return 1
    fi
    
    if [ -z "$pods_list" ]; then
        echo -e "${WARN} Aucun pod trouvé dans le namespace ${NAMESPACE}"
        return 1
    fi
    
    # Afficher la liste des pods
    echo "$pods_list" | nl -w2 -s') '
    
    # Vérifier si le pod actuel existe
    if [ -n "${!var_name}" ]; then
        if echo "$pods_list" | grep -q "^${!var_name}$"; then
            echo -e "${CHECK_MARK} Le pod ${!var_name} existe."
            return 0
        else
            echo -e "${CROSS_MARK} Le pod ${!var_name} n'existe pas."
        fi
    fi
    
    # Demander à l'utilisateur de sélectionner un pod
    while true; do
        echo
        echo -e "${INFO} $description"
        echo -e "${INFO} Entrez le numéro ou le nom complet du pod:"
        read pod_selection
        
        # Vérifier si l'entrée est un numéro
        if [[ "$pod_selection" =~ ^[0-9]+$ ]]; then
            # Obtenir le pod correspondant au numéro
            selected_pod=$(echo "$pods_list" | sed -n "${pod_selection}p")
            if [ -n "$selected_pod" ]; then
                pod_selection=$selected_pod
            else
                echo -e "${CROSS_MARK} Numéro invalide"
                continue
            fi
        fi
        
        # Vérifier si le pod existe
        if echo "$pods_list" | grep -q "^${pod_selection}$"; then
            echo -e "${CHECK_MARK} Pod sélectionné: $pod_selection"
            update_env_value "$var_name" "$pod_selection"
            export "$var_name=$pod_selection"
            return 0
        else
            echo -e "${CROSS_MARK} Pod invalide, veuillez réessayer"
        fi
    done
}

# Fonction pour vérifier le statut d'un pod et le secret
check_pod_status() {
    local pod_name=$1
    local namespace=$2
    local secret_name=$3
    
    # Vérifier le statut du pod
    local pod_status
    pod_status=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null)
    
    if [ "$pod_status" != "Running" ]; then
        echo -e "${CROSS_MARK} Le pod '$pod_name' n'est pas en état 'Running' (état actuel: $pod_status)"
        
        # 1. Vérifier si le script de création de secret a été lancé
        echo -e "\n${INFO} Vérification du secret "$secret_name"..."
        
        if ! kubectl get secret "$secret_name" -n "$namespace" &>/dev/null; then
            echo -e "${WARN} Le secret "$secret_name" n'existe pas."
            echo -e "${INFO} Voulez-vous lancer le script creer_secret_postgres.sh? (o/n)"
            read -r response
            
            if [[ "$response" =~ ^[Oo]$ ]]; then
                echo -e "${INFO} Lancement du script creer_secret_postgres.sh..."
                
                # Vérifier si le script existe dans le dossier courant
                if [ -f "./creer_secret_postgres.sh" ]; then
                    bash ./creer_secret_postgres.sh || {
                        echo -e "${CROSS_MARK} Erreur lors de l'exécution du script de création de secret"
                        return 1
                    }
                else
                    echo -e "${CROSS_MARK} Le script creer_secret_postgres.sh n'existe pas dans le dossier courant"
                    return 1
                fi
            else
                echo -e "${WARN} Le secret doit être créé pour que le pod fonctionne correctement"
                return 1
            fi
        else
            echo -e "${CHECK_MARK} Le secret "$secret_name" existe"
        fi
        
        # 2. Vérifier ArgoCD
        echo -e "\n${INFO} Vérification de l'application dans ArgoCD..."
        
        # Vérifier si argocd CLI est installé
        if ! command -v argocd &>/dev/null; then
            echo -e "${WARN} La commande argocd n'est pas installée."
            echo -e "${INFO} Veuillez vérifier l'état de l'application dans l'interface web d'ArgoCD"
        else
            echo -e "${INFO} Statut de l'application dans ArgoCD :"
            argocd app get postgres-app -o wide || {
                echo -e "${WARN} Impossible d'obtenir le statut de l'application dans ArgoCD"
                echo -e "${INFO} Veuillez vérifier manuellement dans l'interface web d'ArgoCD"
            }
        fi
        
        echo -e "\n${INFO} Actions recommandées :"
        echo -e "1. Vérifier que le secret "$secret_name" est correctement créé"
        echo -e "2. Vérifier l'état de l'application dans ArgoCD"
        echo -e "3. Vérifier les logs du pod avec : kubectl logs $pod_name -n $namespace"
        
        return 1
    fi
    
    return 0
}

# Vérifier toutes les variables nécessaires
check_and_ask_variable "NAMESPACE" "Entrez le namespace"
check_and_ask_variable "POSTGRES_DB_GRANT" "Entrez le nom de la base de données admin"
check_and_ask_variable "POSTGRES_USER_GRANT" "Entrez le nom de l'utilisateur admin"
check_and_ask_variable "POSTGRES_PASSWORD_GRANT" "Entrez le mot de passe admin"
check_and_ask_variable "DAGSTER_DB" "Entrez le nom de la nouvelle base de données"
check_and_ask_variable "DAGSTER_USER" "Entrez le nom du nouvel utilisateur"
check_and_ask_variable "DAGSTER_PASSWORD" "Entrez le mot de passe du nouvel utilisateur"
check_and_ask_variable "DAGSTER_NAME_SECRET" "Entrez le nom du secret postgress à utililiser"

echo -e "${CHECK_MARK} Configuration chargée avec succès"

# Step 2: Vérification du namespace
print_step "2" "Vérification du namespace..."
echo -e "${INFO} Utilisation du namespace: ${NAMESPACE}"

# Add this near the start of your script, after setting NAMESPACE
if ! check_namespace "$NAMESPACE"; then
    echo "❌ Erreur critique: Impossible de configurer le namespace."
    exit 1
fi

if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
    handle_error "Le namespace '$NAMESPACE' n'existe pas."
fi

echo -e "${CHECK_MARK} Namespace vérifié avec succès"

# Step 3: Sélection du pod
print_step "3" "Sélection du pod..."
check_and_ask_variable_pod "POSTGRES_POD" " Entrez le nom du pod à utiliser :" "${NAMESPACE}"

# Vérifier le statut du pod avec la nouvelle fonction
if ! check_pod_status "$POSTGRES_POD" "$NAMESPACE" "$NAME_SECRET"; then
    read -p "Voulez-vous réessayer avec un autre pod? (o/n) " retry
    if [[ "$retry" =~ ^[Oo]$ ]]; then
        # Réinitialiser la variable POSTGRES_POD pour forcer une nouvelle sélection
        POSTGRES_POD=""
        check_and_ask_variable_pod "POSTGRES_POD" "Entrez le nom du pod à utiliser :" "${NAMESPACE}"
    else
        handle_error "Opération annulée par l'utilisateur"
    fi
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