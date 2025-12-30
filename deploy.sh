#!/bin/bash

set -e

# ============================================
# HELPER FUNCTIONS
# ============================================

print_usage() {
    echo "Usage: $0 <command> <environment>"
    echo ""
    echo "Commands:"
    echo "  up      Deploy the full URL Shortener stack"
    echo "  down    Tear down the full URL Shortener stack"
    echo ""
    echo "Environment:"
    echo "  staging     Deploy/destroy staging environment"
    echo "  production  Deploy/destroy production environment"
    echo ""
    echo "Examples:"
    echo "  $0 up staging       # Deploy staging environment"
    echo "  $0 down production  # Tear down production environment"
}

# ============================================
# CONFIGURATION
# ============================================

setup_config() {
    local env="$1"
    
    # Application configuration
    APP_NAMESPACE="url-shortener-${env}"
    APP_RELEASE_NAME="url-shortener-${env}"
    
    # PostgreSQL configuration
    PG_RELEASE_NAME="url-shortener-postgresql-${env}"
    PG_NAMESPACE="url-shortener-postgresql-${env}"
    PG_DATABASE="url_shortener_${env}"
    
    # Redis configuration
    REDIS_RELEASE_NAME="url-shortener-redis-${env}"
    REDIS_NAMESPACE="url-shortener-redis-${env}"
    
    # Environment-specific ports
    if [ "$env" == "staging" ]; then
        PG_NODE_PORT="30432"
        REDIS_NODE_PORT="30380"
        API_NODE_PORT="30080"
        ASPNETCORE_ENV="Staging"
    else
        PG_NODE_PORT="30433"
        REDIS_NODE_PORT="30381"
        API_NODE_PORT="30081"
        ASPNETCORE_ENV="Production"
    fi
}

# ============================================
# UP (DEPLOY) FUNCTIONS
# ============================================

deploy_postgresql() {
    echo -n "[1/4] Deploying PostgreSQL... "
    
    # Generate random credentials
    local random_number=$(od -An -tu4 -N4 /dev/urandom | tr -d ' ')
    PG_USER="url_shortener_${random_number}"
    PG_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24)
    PG_ADMIN_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)
    
    # Add Bitnami repo if not exists
    helm repo add bitnami https://charts.bitnami.com/bitnami &>/dev/null || true
    helm repo update &>/dev/null
    
    # Create namespace
    kubectl create namespace "$PG_NAMESPACE" --dry-run=client -o yaml 2>/dev/null | kubectl apply -f - &>/dev/null
    
    # Install PostgreSQL
    helm upgrade --install "$PG_RELEASE_NAME" bitnami/postgresql \
        --namespace "$PG_NAMESPACE" \
        --set auth.postgresPassword="$PG_ADMIN_PASSWORD" \
        --set auth.username="$PG_USER" \
        --set auth.password="$PG_PASSWORD" \
        --set auth.database="$PG_DATABASE" \
        --set primary.service.type=NodePort \
        --set-string primary.service.nodePorts.postgresql="$PG_NODE_PORT" \
        --wait &>/dev/null
    
    # Wait for PostgreSQL to be ready
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=postgresql \
        -n "$PG_NAMESPACE" \
        --timeout=180s &>/dev/null
    
    # Set service details
    PG_SERVICE_HOST="${PG_RELEASE_NAME}.${PG_NAMESPACE}.svc.cluster.local"
    PG_SERVICE_PORT="5432"
    
    echo "Done"
}

deploy_redis() {
    echo -n "[2/4] Deploying Redis... "
    
    # Generate random credentials
    local random_number=$(od -An -tu4 -N4 /dev/urandom | tr -d ' ')
    REDIS_USER="url_shortener_${random_number}"
    REDIS_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24)
    REDIS_ADMIN_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)
    
    # Create namespace
    kubectl create namespace "$REDIS_NAMESPACE" --dry-run=client -o yaml 2>/dev/null | kubectl apply -f - &>/dev/null
    
    # Install Redis
    helm upgrade --install "$REDIS_RELEASE_NAME" bitnami/redis \
        --namespace "$REDIS_NAMESPACE" \
        --set architecture=standalone \
        --set auth.password="$REDIS_ADMIN_PASSWORD" \
        --set master.service.type=NodePort \
        --set-string master.service.nodePorts.redis="$REDIS_NODE_PORT" \
        --wait &>/dev/null
    
    # Wait for Redis to be ready
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=redis \
        -n "$REDIS_NAMESPACE" \
        --timeout=120s &>/dev/null
    
    # Create Redis user with ACL
    kubectl exec -n "$REDIS_NAMESPACE" "${REDIS_RELEASE_NAME}-master-0" -- \
        redis-cli -a "$REDIS_ADMIN_PASSWORD" \
        ACL SETUSER "$REDIS_USER" on ">$REDIS_PASSWORD" "~*" "+@all" &>/dev/null
    
    # Save ACL
    kubectl exec -n "$REDIS_NAMESPACE" "${REDIS_RELEASE_NAME}-master-0" -- \
        redis-cli -a "$REDIS_ADMIN_PASSWORD" ACL SAVE &>/dev/null
    
    # Set service details
    REDIS_SERVICE_HOST="${REDIS_RELEASE_NAME}-master.${REDIS_NAMESPACE}.svc.cluster.local"
    REDIS_SERVICE_PORT="6379"
    
    echo "Done"
}

create_app_secrets() {
    echo -n "[3/4] Creating Secrets... "
    
    # Create namespace
    kubectl create namespace "$APP_NAMESPACE" --dry-run=client -o yaml 2>/dev/null | kubectl apply -f - &>/dev/null
    
    # Build connection strings
    PG_CONNECTION_STRING="Host=${PG_SERVICE_HOST};Port=${PG_SERVICE_PORT};Database=${PG_DATABASE};Username=${PG_USER};Password=${PG_PASSWORD}"
    REDIS_CONNECTION_STRING="${REDIS_SERVICE_HOST}:${REDIS_SERVICE_PORT},user=${REDIS_USER},password=${REDIS_PASSWORD}"
    
    # Delete existing secret if exists
    kubectl delete secret url-shortener-secrets -n "$APP_NAMESPACE" --ignore-not-found &>/dev/null
    
    # Create secrets
    kubectl create secret generic url-shortener-secrets \
        --namespace "$APP_NAMESPACE" \
        --from-literal=ASPNETCORE_ENVIRONMENT="$ASPNETCORE_ENV" \
        --from-literal=ConnectionStrings__Database="$PG_CONNECTION_STRING" \
        --from-literal=ConnectionStrings__Redis="$REDIS_CONNECTION_STRING" \
        --from-literal=Url__CacheExpiresInDays="1" \
        --from-literal=Url__CodeLength="6" &>/dev/null
    
    echo "Done"
}

deploy_application() {
    echo -n "[4/4] Deploying Application... "
    
    # Ensure url-shortener repo is added
    helm repo add url-shortener https://recepgunes1.github.io/Url-Shortener &>/dev/null || true
    helm repo update &>/dev/null
    
    # Install URL Shortener application with NodePort
    helm upgrade --install "$APP_RELEASE_NAME" url-shortener/url-shortener \
        --namespace "$APP_NAMESPACE" \
        --set envFrom[0].secretRef.name=url-shortener-secrets \
        --set service.type=NodePort \
        --set service.nodePort="$API_NODE_PORT" \
        --wait &>/dev/null
    
    echo "Done"
}

print_connection_info() {
    local env="$1"
    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    
    echo ""
    echo "============================================"
    echo "DEPLOYMENT COMPLETE - $env"
    echo "============================================"
    echo ""
    echo "External Access (Node IP: $node_ip)"
    echo "--------------------------------------------"
    echo ""
    echo "psql:"
    echo "  psql \"postgresql://$PG_USER:$PG_PASSWORD@$node_ip:$PG_NODE_PORT/$PG_DATABASE\""
    echo ""
    echo "redis-cli:"
    echo "  redis-cli -h $node_ip -p $REDIS_NODE_PORT --user $REDIS_USER --pass $REDIS_PASSWORD"
    echo ""
    echo "API:"
    echo "  http://$node_ip:$API_NODE_PORT"
    echo ""
    echo "--------------------------------------------"
    echo "============================================"
}

# ============================================
# DOWN (TEARDOWN) FUNCTIONS
# ============================================

teardown_application() {
    echo -n "[1/4] Removing Application... "
    if helm status "$APP_RELEASE_NAME" -n "$APP_NAMESPACE" &>/dev/null; then
        helm uninstall "$APP_RELEASE_NAME" -n "$APP_NAMESPACE" &>/dev/null
    fi
    echo "Done"
}

teardown_secrets() {
    echo -n "[2/4] Removing Secrets... "
    kubectl delete secret url-shortener-secrets -n "$APP_NAMESPACE" --ignore-not-found &>/dev/null
    if kubectl get namespace "$APP_NAMESPACE" &>/dev/null; then
        kubectl delete namespace "$APP_NAMESPACE" --wait=true --timeout=60s &>/dev/null
    fi
    echo "Done"
}

teardown_redis() {
    echo -n "[3/4] Removing Redis... "
    if helm status "$REDIS_RELEASE_NAME" -n "$REDIS_NAMESPACE" &>/dev/null; then
        helm uninstall "$REDIS_RELEASE_NAME" -n "$REDIS_NAMESPACE" &>/dev/null
    fi
    kubectl delete pvc -n "$REDIS_NAMESPACE" -l app.kubernetes.io/name=redis --ignore-not-found &>/dev/null
    if kubectl get namespace "$REDIS_NAMESPACE" &>/dev/null; then
        kubectl delete namespace "$REDIS_NAMESPACE" --wait=true --timeout=60s &>/dev/null
    fi
    echo "Done"
}

teardown_postgresql() {
    echo -n "[4/4] Removing PostgreSQL... "
    if helm status "$PG_RELEASE_NAME" -n "$PG_NAMESPACE" &>/dev/null; then
        helm uninstall "$PG_RELEASE_NAME" -n "$PG_NAMESPACE" &>/dev/null
    fi
    kubectl delete pvc -n "$PG_NAMESPACE" -l app.kubernetes.io/name=postgresql --ignore-not-found &>/dev/null
    if kubectl get namespace "$PG_NAMESPACE" &>/dev/null; then
        kubectl delete namespace "$PG_NAMESPACE" --wait=true --timeout=60s &>/dev/null
    fi
    echo "Done"
}

# ============================================
# MAIN EXECUTION
# ============================================

do_up() {
    local env="$1"
    
    echo "Deploying URL Shortener ($env)..."
    echo ""
    
    setup_config "$env"
    
    deploy_postgresql
    deploy_redis
    create_app_secrets
    deploy_application
    
    print_connection_info "$env"
}

do_down() {
    local env="$1"
    
    echo "Tearing down URL Shortener ($env)..."
    echo ""
    
    setup_config "$env"
    
    teardown_application
    teardown_secrets
    teardown_redis
    teardown_postgresql
    
    echo ""
    echo "Teardown complete for $env environment."
}

# ============================================
# ARGUMENT PARSING
# ============================================

if [ -z "$1" ] || [ -z "$2" ]; then
    print_usage
    exit 1
fi

COMMAND="$1"
ENV="$2"

if [ "$ENV" != "staging" ] && [ "$ENV" != "production" ]; then
    echo "Error: Environment must be 'staging' or 'production'"
    exit 1
fi

case "$COMMAND" in
    up)
        do_up "$ENV"
        ;;
    down)
        do_down "$ENV"
        ;;
    *)
        echo "Error: Unknown command '$COMMAND'"
        print_usage
        exit 1
        ;;
esac
