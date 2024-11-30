# Guide de connexion à PostgreSQL dans Kubernetes

Ce guide explique comment se connecter à votre base de données PostgreSQL de deux façons différentes : via la ligne de commande (CLI) et via un client graphique (DBeaver).

## 1. Test de connexion via ligne de commande

### Prérequis
- Accès au cluster Kubernetes
- kubectl configuré
- Les secrets PostgreSQL configurés

### Étapes de test

1. **Vérifier que le pod PostgreSQL est en cours d'exécution**
```bash
# Remplacer <namespace> par votre namespace (ex: postgres)
kubectl get pods -n <namespace>
```

2. **Se connecter en tant qu'administrateur**
```bash
# Remplacer les variables selon votre configuration
kubectl exec -it <pod-name> -n <namespace> -- \
    psql -U <admin-user> -d <admin-db>

```

3. **Se connecter en tant qu'utilisateur Dagster**
```bash
kubectl exec -it <pod-name> -n <namespace> -- \
    env PGPASSWORD=<password> psql -U <dagster-user> -d <dagster-db>

```

4. **Tester la connexion avec une requête simple**
```sql
-- Une fois connecté à psql :
SELECT current_database(), current_user, version();
\l  -- Liste toutes les bases de données
\du -- Liste tous les utilisateurs
\q  -- Quitter psql
```

## 2. Connexion via DBeaver

### Prérequis
- DBeaver installé sur votre machine
- Accès au cluster Kubernetes
- kubectl configuré

### Étapes de configuration

1. **Créer un port-forward vers PostgreSQL**
```bash
# Garder cette commande en cours d'exécution dans un terminal dédié
kubectl port-forward service/postgres -n postgres 5432:5432
```

2. **Configurer une nouvelle connexion dans DBeaver**
   - Ouvrir DBeaver
   - Cliquer sur "Nouvelle Connexion"
   - Sélectionner "PostgreSQL"
   - Remplir les champs suivants :
     ```
     Host: localhost
     Port: 5432
     Database: <database_name> (ou votre DAGSTER_DB)
     Username: <user> (ou votre DAGSTER_USER)
     Password: <password> (ou votre DAGSTER_PASSWORD)
     ```
   - Dans l'onglet "Driver properties" :
     - SSL Mode: disable

3. **Tester la connexion**
   - Cliquer sur "Test Connection" pour vérifier que tout fonctionne
   - Si le test réussit, cliquer sur "Finish"

### Notes importantes
- Le port-forward doit rester actif pendant l'utilisation de DBeaver
- Si vous fermez le terminal avec le port-forward, vous devrez le relancer
- Assurez-vous que le port 5432 n'est pas déjà utilisé sur votre machine

### Dépannage
1. **Erreur de connexion :**
   - Vérifier que le port-forward est actif
   - Vérifier que les identifiants sont corrects
   - Vérifier que le pod PostgreSQL est en cours d'exécution

2. **Port déjà utilisé :**
   ```bash
   # Utilisez un port différent si 5432 est occupé
   kubectl port-forward service/postgres -n postgres 5433:5432
   ```
   Puis dans DBeaver, utilisez le port 5433

3. **Vérifier les logs PostgreSQL :**
   ```bash
   kubectl logs <pod-name> -n <namespace>
   ```
