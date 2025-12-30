#!/bin/bash

set -e

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
}

setup_config() {
    local env="$1"
    
    APP_NAMESPACE="url-shortener-${env}"
    APP_RELEASE_NAME="url-shortener-${env}"
    
    PG_RELEASE_NAME="url-shortener-postgresql-${env}"
    PG_NAMESPACE="url-shortener-postgresql-${env}"
    PG_DATABASE="url_shortener_${env}"
    
    REDIS_RELEASE_NAME="url-shortener-redis-${env}"
    REDIS_NAMESPACE="url-shortener-redis-${env}"
    
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

deploy_postgresql() {
    echo "Deploying PostgreSQL..."
    
    local random_number=$(od -An -tu4 -N4 /dev/urandom | tr -d ' ')
    PG_USER="url_shortener_${random_number}"
    PG_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24)
    PG_ADMIN_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)
    
    helm repo add bitnami https://charts.bitnami.com/bitnami &>/dev/null || true
    helm repo update &>/dev/null
    
    kubectl create namespace "$PG_NAMESPACE" --dry-run=client -o yaml 2>/dev/null | kubectl apply -f - &>/dev/null
    
    helm upgrade --install "$PG_RELEASE_NAME" bitnami/postgresql \
        --namespace "$PG_NAMESPACE" \
        --set auth.postgresPassword="$PG_ADMIN_PASSWORD" \
        --set auth.username="$PG_USER" \
        --set auth.password="$PG_PASSWORD" \
        --set auth.database="$PG_DATABASE" \
        --set primary.service.type=NodePort \
        --set-string primary.service.nodePorts.postgresql="$PG_NODE_PORT" \
        --wait &>/dev/null
    
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=postgresql \
        -n "$PG_NAMESPACE" \
        --timeout=180s &>/dev/null
    
    PG_SERVICE_HOST="${PG_RELEASE_NAME}.${PG_NAMESPACE}.svc.cluster.local"
    PG_SERVICE_PORT="5432"
}

deploy_redis() {
    echo "Deploying Redis..."
    
    local random_number=$(od -An -tu4 -N4 /dev/urandom | tr -d ' ')
    REDIS_USER="url_shortener_${random_number}"
    REDIS_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24)
    REDIS_ADMIN_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)
    
    kubectl create namespace "$REDIS_NAMESPACE" --dry-run=client -o yaml 2>/dev/null | kubectl apply -f - &>/dev/null
    
    helm upgrade --install "$REDIS_RELEASE_NAME" bitnami/redis \
        --namespace "$REDIS_NAMESPACE" \
        --set architecture=standalone \
        --set auth.password="$REDIS_ADMIN_PASSWORD" \
        --set master.service.type=NodePort \
        --set-string master.service.nodePorts.redis="$REDIS_NODE_PORT" \
        --wait &>/dev/null
    
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=redis \
        -n "$REDIS_NAMESPACE" \
        --timeout=120s &>/dev/null
    
    kubectl exec -n "$REDIS_NAMESPACE" "${REDIS_RELEASE_NAME}-master-0" -- \
        redis-cli -a "$REDIS_ADMIN_PASSWORD" \
        ACL SETUSER "$REDIS_USER" on ">$REDIS_PASSWORD" "~*" "+@all" &>/dev/null
    
    kubectl exec -n "$REDIS_NAMESPACE" "${REDIS_RELEASE_NAME}-master-0" -- \
        redis-cli -a "$REDIS_ADMIN_PASSWORD" ACL SAVE &>/dev/null
    
    REDIS_SERVICE_HOST="${REDIS_RELEASE_NAME}-master.${REDIS_NAMESPACE}.svc.cluster.local"
    REDIS_SERVICE_PORT="6379"
}

create_app_secrets() {
    echo "Creating Secrets..."
    
    kubectl create namespace "$APP_NAMESPACE" --dry-run=client -o yaml 2>/dev/null | kubectl apply -f - &>/dev/null
    
    PG_CONNECTION_STRING="Host=${PG_SERVICE_HOST};Port=${PG_SERVICE_PORT};Database=${PG_DATABASE};Username=${PG_USER};Password=${PG_PASSWORD}"
    REDIS_CONNECTION_STRING="${REDIS_SERVICE_HOST}:${REDIS_SERVICE_PORT},user=${REDIS_USER},password=${REDIS_PASSWORD}"
    
    kubectl delete secret url-shortener-secrets -n "$APP_NAMESPACE" --ignore-not-found &>/dev/null
    
    kubectl create secret generic url-shortener-secrets \
        --namespace "$APP_NAMESPACE" \
        --from-literal=ASPNETCORE_ENVIRONMENT="$ASPNETCORE_ENV" \
        --from-literal=ConnectionStrings__Database="$PG_CONNECTION_STRING" \
        --from-literal=ConnectionStrings__Redis="$REDIS_CONNECTION_STRING" \
        --from-literal=Url__CacheExpiresInDays="1" \
        --from-literal=Url__CodeLength="6" &>/dev/null
}

deploy_application() {
    echo "Deploying Application..."
    
    helm repo add url-shortener https://recepgunes1.github.io/Url-Shortener &>/dev/null || true
    helm repo update &>/dev/null
    
    helm upgrade --install "$APP_RELEASE_NAME" url-shortener/url-shortener \
        --namespace "$APP_NAMESPACE" \
        --set envFrom[0].secretRef.name=url-shortener-secrets \
        --set service.type=NodePort \
        --set service.nodePort="$API_NODE_PORT" \
        --wait &>/dev/null
}

print_connection_info() {
    local env="$1"
    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    
    echo ""
    echo "Deployment complete ($env)"
    echo ""
    echo "PostgreSQL:  psql \"postgresql://$PG_USER:$PG_PASSWORD@$node_ip:$PG_NODE_PORT/$PG_DATABASE\""
    echo "Redis:       redis-cli -h $node_ip -p $REDIS_NODE_PORT --user $REDIS_USER --pass $REDIS_PASSWORD"
    echo "API:         http://$node_ip:$API_NODE_PORT"
    echo ""
}

test_stack() {
  bash "$(dirname "$0")/test-postgresql-connection.sh" "$node_ip" "$PG_NODE_PORT" "$PG_USER" "$PG_PASSWORD" "$PG_DATABASE"
  bash "$(dirname "$0")/test-redis-connection.sh" "$node_ip" "$REDIS_NODE_PORT" "$REDIS_USER" "$REDIS_PASSWORD"
}

teardown_application() {
    echo "Removing Application..."
    helm status "$APP_RELEASE_NAME" -n "$APP_NAMESPACE" &>/dev/null && \
        helm uninstall "$APP_RELEASE_NAME" -n "$APP_NAMESPACE" &>/dev/null || true
}

teardown_secrets() {
    echo "Removing Secrets..."
    kubectl delete secret url-shortener-secrets -n "$APP_NAMESPACE" --ignore-not-found &>/dev/null
    kubectl get namespace "$APP_NAMESPACE" &>/dev/null && \
        kubectl delete namespace "$APP_NAMESPACE" --wait=true --timeout=60s &>/dev/null || true
}

teardown_redis() {
    echo "Removing Redis..."
    helm status "$REDIS_RELEASE_NAME" -n "$REDIS_NAMESPACE" &>/dev/null && \
        helm uninstall "$REDIS_RELEASE_NAME" -n "$REDIS_NAMESPACE" &>/dev/null || true
    kubectl delete pvc -n "$REDIS_NAMESPACE" -l app.kubernetes.io/name=redis --ignore-not-found &>/dev/null
    kubectl get namespace "$REDIS_NAMESPACE" &>/dev/null && \
        kubectl delete namespace "$REDIS_NAMESPACE" --wait=true --timeout=60s &>/dev/null || true
}

teardown_postgresql() {
    echo "Removing PostgreSQL..."
    helm status "$PG_RELEASE_NAME" -n "$PG_NAMESPACE" &>/dev/null && \
        helm uninstall "$PG_RELEASE_NAME" -n "$PG_NAMESPACE" &>/dev/null || true
    kubectl delete pvc -n "$PG_NAMESPACE" -l app.kubernetes.io/name=postgresql --ignore-not-found &>/dev/null
    kubectl get namespace "$PG_NAMESPACE" &>/dev/null && \
        kubectl delete namespace "$PG_NAMESPACE" --wait=true --timeout=60s &>/dev/null || true
}

do_up() {
    local env="$1"
    echo "Deploying URL Shortener ($env)..."
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
    setup_config "$env"
    teardown_application
    teardown_secrets
    teardown_redis
    teardown_postgresql
    echo "Teardown complete"
}

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
    up)   do_up "$ENV" ;;
    down) do_down "$ENV" ;;
    *)    echo "Error: Unknown command '$COMMAND'"; print_usage; exit 1 ;;
esac
