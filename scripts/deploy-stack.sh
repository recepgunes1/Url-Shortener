#!/bin/bash

# Exit immediately if any command fails
set -e

# Displays help message with available commands and options
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

# Sets up environment-specific configuration variables
setup_config() {
    local env="$1"
    
    # Application namespace and Helm release name
    APP_NAMESPACE="url-shortener-${env}"
    APP_RELEASE_NAME="url-shortener-${env}"
    
    # PostgreSQL configuration
    PG_RELEASE_NAME="url-shortener-postgresql-${env}"
    PG_NAMESPACE="url-shortener-postgresql-${env}"
    PG_DATABASE="url_shortener_${env}"
    
    # Redis configuration
    REDIS_RELEASE_NAME="url-shortener-redis-${env}"
    REDIS_NAMESPACE="url-shortener-redis-${env}"
    
    # Jaeger configuration
    JAEGER_RELEASE_NAME="url-shortener-jaeger-${env}"
    JAEGER_NAMESPACE="url-shortener-jaeger-${env}"
    
    # Environment-specific port assignments
    if [ "$env" == "staging" ]; then
        PG_NODE_PORT="30432"            # PostgreSQL external port for staging
        REDIS_NODE_PORT="30380"         # Redis external port for staging
        API_NODE_PORT="30080"           # API external port for staging
        JAEGER_UI_NODE_PORT="30686"     # Jaeger UI for staging
        JAEGER_OTLP_NODE_PORT="30417"   # OTLP gRPC endpoint for staging
        ASPNETCORE_ENV="Staging"
    else
        PG_NODE_PORT="30433"            # PostgreSQL external port for production
        REDIS_NODE_PORT="30381"         # Redis external port for production
        API_NODE_PORT="30081"           # API external port for production
        JAEGER_UI_NODE_PORT="30687"     # Jaeger UI for production
        JAEGER_OTLP_NODE_PORT="30418"   # OTLP gRPC endpoint for production
        ASPNETCORE_ENV="Production"
    fi
}

# Deploys Jaeger using the official Helm chart
deploy_jaeger() {
    echo "Deploying Jaeger..."
    
    # Add Jaeger Helm repository
    helm repo add jaegertracing https://jaegertracing.github.io/helm-charts &>/dev/null || true
    helm repo update &>/dev/null
    
    # Create namespace idempotently
    kubectl create namespace "$JAEGER_NAMESPACE" --dry-run=client -o yaml 2>/dev/null | kubectl apply -f - &>/dev/null
    
    # Deploy Jaeger all-in-one with in-memory storage
    helm upgrade --install "$JAEGER_RELEASE_NAME" jaegertracing/jaeger \
        --namespace "$JAEGER_NAMESPACE" \
        --set provisionDataStore.cassandra=false \
        --set allInOne.enabled=true \
        --set storage.type=memory \
        --set agent.enabled=false \
        --set collector.enabled=false \
        --set query.enabled=false \
        --wait &>/dev/null
    
    # Get the actual service name created by the chart
    local svc_name
    svc_name=$(kubectl get svc -n "$JAEGER_NAMESPACE" -l "app.kubernetes.io/instance=${JAEGER_RELEASE_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$svc_name" ]; then
        echo "Error: Could not find Jaeger service"
        exit 1
    fi
    
    # Find port indices for UI (16686) and OTLP gRPC (4317)
    local ui_port_index otlp_port_index
    ui_port_index=$(kubectl get svc "$svc_name" -n "$JAEGER_NAMESPACE" -o json | \
        jq '.spec.ports | to_entries[] | select(.value.port == 16686) | .key')
    otlp_port_index=$(kubectl get svc "$svc_name" -n "$JAEGER_NAMESPACE" -o json | \
        jq '.spec.ports | to_entries[] | select(.value.port == 4317) | .key')
    
    # Patch service: change type to NodePort AND set specific nodePort values in one operation
    # Must change type first, then nodePort values can be assigned
    kubectl patch svc "$svc_name" -n "$JAEGER_NAMESPACE" --type='json' -p='[
        {"op": "replace", "path": "/spec/type", "value": "NodePort"},
        {"op": "add", "path": "/spec/ports/'"$ui_port_index"'/nodePort", "value": '"$JAEGER_UI_NODE_PORT"'},
        {"op": "add", "path": "/spec/ports/'"$otlp_port_index"'/nodePort", "value": '"$JAEGER_OTLP_NODE_PORT"'}
    ]' &>/dev/null
    
    # Set internal service connection details for other components
    JAEGER_OTLP_ENDPOINT="http://${svc_name}.${JAEGER_NAMESPACE}.svc.cluster.local:4317"
}

# Deploys PostgreSQL using the Bitnami Helm chart
deploy_postgresql() {
    echo "Deploying PostgreSQL..."
    
    # Generate random username suffix using /dev/urandom for uniqueness
    local random_number=$(od -An -tu4 -N4 /dev/urandom | tr -d ' ')
    PG_USER="url_shortener_${random_number}"
    
    # Generate secure random passwords
    # - User password: 24 alphanumeric characters
    # - Admin password: 32 alphanumeric characters (postgres superuser)
    PG_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24)
    PG_ADMIN_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)
    
    # Add Bitnami Helm repository (ignore errors if already added)
    helm repo add bitnami https://charts.bitnami.com/bitnami &>/dev/null || true
    helm repo update &>/dev/null
    
    # Create namespace idempotently using dry-run + apply pattern
    kubectl create namespace "$PG_NAMESPACE" --dry-run=client -o yaml 2>/dev/null | kubectl apply -f - &>/dev/null
    
    # Deploy PostgreSQL with Helm
    # Authentication credentials, NodePort service for external access, Daily backup cronjob with persistent storage
    helm upgrade --install "$PG_RELEASE_NAME" bitnami/postgresql \
        --namespace "$PG_NAMESPACE" \
        --set auth.postgresPassword="$PG_ADMIN_PASSWORD" \
        --set auth.username="$PG_USER" \
        --set auth.password="$PG_PASSWORD" \
        --set auth.database="$PG_DATABASE" \
        --set primary.service.type=NodePort \
        --set-string primary.service.nodePorts.postgresql="$PG_NODE_PORT" \
        --set backup.enabled=true \
        --set backup.cronjob.schedule="0 2 * * *" \
        --set backup.cronjob.timeZone="UTC" \
        --set backup.cronjob.concurrencyPolicy="Forbid" \
        --set backup.cronjob.storage.enabled=true \
        --set backup.cronjob.storage.size="5Gi" \
        --set backup.cronjob.storage.storageClass="" \
        &>/dev/null
    
    # Wait for PostgreSQL StatefulSet to be ready (timeout: 3 minutes)
    kubectl rollout status statefulset/"${PG_RELEASE_NAME}" \
        -n "$PG_NAMESPACE" \
        --timeout=180s &>/dev/null
    
    # Set internal service connection details for other components
    PG_SERVICE_HOST="${PG_RELEASE_NAME}.${PG_NAMESPACE}.svc.cluster.local"
    PG_SERVICE_PORT="5432"
}

# Deploys Redis using the Bitnami Helm chart
deploy_redis() {
    echo "Deploying Redis..."
    
    # Generate random username suffix for uniqueness
    local random_number=$(od -An -tu4 -N4 /dev/urandom | tr -d ' ')
    REDIS_USER="url_shortener_${random_number}"
    
    # Generate secure random passwords
    # - User password: 24 alphanumeric characters
    # - Admin password: 32 alphanumeric characters (default user)
    REDIS_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24)
    REDIS_ADMIN_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)
    
    # Add Bitnami Helm repository (ignore errors if already added)
    helm repo add bitnami https://charts.bitnami.com/bitnami &>/dev/null || true
    helm repo update &>/dev/null

    # Create namespace idempotently
    kubectl create namespace "$REDIS_NAMESPACE" --dry-run=client -o yaml 2>/dev/null | kubectl apply -f - &>/dev/null
    
    # Deploy Redis with Helm
    # Using standalone architecture (single master, no replicas), NodePort service for external access
    helm upgrade --install "$REDIS_RELEASE_NAME" bitnami/redis \
        --namespace "$REDIS_NAMESPACE" \
        --set architecture=standalone \
        --set auth.password="$REDIS_ADMIN_PASSWORD" \
        --set master.service.type=NodePort \
        --set-string master.service.nodePorts.redis="$REDIS_NODE_PORT" \
        --wait &>/dev/null
    
    # Wait for Redis pod to be ready (timeout: 2 minutes)
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=redis \
        -n "$REDIS_NAMESPACE" \
        --timeout=120s &>/dev/null
    
    # Create dedicated ACL user for the application
    kubectl exec -n "$REDIS_NAMESPACE" "${REDIS_RELEASE_NAME}-master-0" -- \
        redis-cli -a "$REDIS_ADMIN_PASSWORD" \
        ACL SETUSER "$REDIS_USER" on ">$REDIS_PASSWORD" "~*" "+@all" &>/dev/null
    
    # Persist ACL changes to disk
    kubectl exec -n "$REDIS_NAMESPACE" "${REDIS_RELEASE_NAME}-master-0" -- \
        redis-cli -a "$REDIS_ADMIN_PASSWORD" ACL SAVE &>/dev/null
    
    # Set internal service connection details for other components
    REDIS_SERVICE_HOST="${REDIS_RELEASE_NAME}-master.${REDIS_NAMESPACE}.svc.cluster.local"
    REDIS_SERVICE_PORT="6379"
}

# Creates Kubernetes secrets for the URL Shortener application
create_app_secrets() {
    echo "Creating Secrets..."
    
    # Create application namespace idempotently
    kubectl create namespace "$APP_NAMESPACE" --dry-run=client -o yaml 2>/dev/null | kubectl apply -f - &>/dev/null
    
    # Build connection strings using internal Kubernetes DNS also format follows .NET connection string conventions
    PG_CONNECTION_STRING="Host=${PG_SERVICE_HOST};Port=${PG_SERVICE_PORT};Database=${PG_DATABASE};Username=${PG_USER};Password=${PG_PASSWORD}"
    REDIS_CONNECTION_STRING="${REDIS_SERVICE_HOST}:${REDIS_SERVICE_PORT},user=${REDIS_USER},password=${REDIS_PASSWORD}"
    
    # Delete existing secret if present (for clean updates)
    kubectl delete secret url-shortener-secrets -n "$APP_NAMESPACE" --ignore-not-found &>/dev/null
    
    # Create new secret with all application configuration
    kubectl create secret generic url-shortener-secrets \
        --namespace "$APP_NAMESPACE" \
        --from-literal=ASPNETCORE_ENVIRONMENT="$ASPNETCORE_ENV" \
        --from-literal=ConnectionStrings__Database="$PG_CONNECTION_STRING" \
        --from-literal=ConnectionStrings__Redis="$REDIS_CONNECTION_STRING" \
        --from-literal=Url__CacheExpiresInDays="1" \
        --from-literal=Url__CodeLength="6" \
        --from-literal=OTEL_EXPORTER_OTLP_ENDPOINT="$JAEGER_OTLP_ENDPOINT" \
        --from-literal=OTEL_EXPORTER_OTLP_PROTOCOL="grpc" &>/dev/null
}

# Deploys the URL Shortener application using its Helm chart
deploy_application() {
    echo "Deploying Application..."
    
    # Add URL Shortener Helm repository (hosted on GitHub Pages)
    helm repo add url-shortener https://recepgunes1.github.io/Url-Shortener &>/dev/null || true
    helm repo update &>/dev/null
    
    # Deploy the application with Helm
    # envFrom: mounts the secret as environment variables
    # service.type: NodePort for external access
    helm upgrade --install "$APP_RELEASE_NAME" url-shortener/url-shortener \
        --namespace "$APP_NAMESPACE" \
        --set envFrom[0].secretRef.name=url-shortener-secrets \
        --set service.type=NodePort \
        --set service.nodePort="$API_NODE_PORT" \
        --wait &>/dev/null
}

# Prints connection information after successful deployment
print_connection_info() {
    local env="$1"
    
    # Get the first node's internal IP address
    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)    
    local api_url="http://$node_ip:$API_NODE_PORT"
    local jaeger_url="http://$node_ip:$JAEGER_UI_NODE_PORT"
    
    # Staging environment includes Scalar API docs endpoint
    if [ "$env" == "staging" ]; then
        api_url="${api_url}/scalar"
    fi
    
    echo ""
    echo "Deployment complete ($env)"
    echo "API: $api_url"
    echo "Jaeger: $jaeger_url"
}

# Runs connectivity tests for PostgreSQL and Redis
test_stack() {
    local env="$1"
    
    # Get node IP for external connection testing
    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)

    echo ""
    echo "Testing stack ($env)..."
    
    # Run PostgreSQL connectivity test
    bash "$(dirname "$0")/test-postgresql-connection.sh" "$APP_NAMESPACE" "$node_ip" "$PG_NODE_PORT"
    
    # Run Redis connectivity test
    bash "$(dirname "$0")/test-redis-connection.sh" "$APP_NAMESPACE" "$node_ip" "$REDIS_NODE_PORT"
}

# Removes the URL Shortener application, checks if the release exists before attempting uninstall
teardown_application() {
    echo "Removing Application..."
    helm status "$APP_RELEASE_NAME" -n "$APP_NAMESPACE" &>/dev/null && \
        helm uninstall "$APP_RELEASE_NAME" -n "$APP_NAMESPACE" &>/dev/null || true
}

# Removes application secrets and namespace
teardown_secrets() {
    echo "Removing Secrets..."
    kubectl delete secret url-shortener-secrets -n "$APP_NAMESPACE" --ignore-not-found &>/dev/null
    kubectl get namespace "$APP_NAMESPACE" &>/dev/null && \
        kubectl delete namespace "$APP_NAMESPACE" --wait=true --timeout=60s &>/dev/null || true
}

# Removes Redis deployment, cleans up Persistent Volume Claims to free storage
teardown_redis() {
    echo "Removing Redis..."
    helm status "$REDIS_RELEASE_NAME" -n "$REDIS_NAMESPACE" &>/dev/null && \
        helm uninstall "$REDIS_RELEASE_NAME" -n "$REDIS_NAMESPACE" &>/dev/null || true
    
    # Delete PVCs to release persistent storage
    kubectl delete pvc -n "$REDIS_NAMESPACE" -l app.kubernetes.io/name=redis --ignore-not-found &>/dev/null
    
    # Delete the namespace
    kubectl get namespace "$REDIS_NAMESPACE" &>/dev/null && \
        kubectl delete namespace "$REDIS_NAMESPACE" --wait=true --timeout=60s &>/dev/null || true
}

# Removes Jaeger deployment
teardown_jaeger() {
    echo "Removing Jaeger..."
    helm status "$JAEGER_RELEASE_NAME" -n "$JAEGER_NAMESPACE" &>/dev/null && \
        helm uninstall "$JAEGER_RELEASE_NAME" -n "$JAEGER_NAMESPACE" &>/dev/null || true
    
    # Delete the namespace
    kubectl get namespace "$JAEGER_NAMESPACE" &>/dev/null && \
        kubectl delete namespace "$JAEGER_NAMESPACE" --wait=true --timeout=60s &>/dev/null || true
}

# Removes PostgreSQL deployment, cleans up Persistent Volume Claims to free storage
teardown_postgresql() {
    echo "Removing PostgreSQL..."
    helm status "$PG_RELEASE_NAME" -n "$PG_NAMESPACE" &>/dev/null && \
        helm uninstall "$PG_RELEASE_NAME" -n "$PG_NAMESPACE" &>/dev/null || true
    
    # Delete PVCs to release persistent storage
    kubectl delete pvc -n "$PG_NAMESPACE" -l app.kubernetes.io/name=postgresql --ignore-not-found &>/dev/null
    
    # Delete the namespace
    kubectl get namespace "$PG_NAMESPACE" &>/dev/null && \
        kubectl delete namespace "$PG_NAMESPACE" --wait=true --timeout=60s &>/dev/null || true
}

# Deploys the complete stack in the correct order
do_up() {
    local env="$1"
    echo "Deploying URL Shortener ($env)..."
    
    setup_config "$env"
    deploy_jaeger
    deploy_postgresql
    deploy_redis
    create_app_secrets
    deploy_application
    print_connection_info "$env"
    test_stack "$env"
}

# Tears down the complete stack in reverse order
do_down() {
    local env="$1"
    echo "Tearing down URL Shortener ($env)..."
    
    setup_config "$env"
    teardown_application
    teardown_secrets
    teardown_redis
    teardown_postgresql
    teardown_jaeger
    
    echo "Teardown complete"
}

# Validate required arguments
if [ -z "$1" ] || [ -z "$2" ]; then
    print_usage
    exit 1
fi

COMMAND="$1"
ENV="$2"

# Validate environment argument
if [ "$ENV" != "staging" ] && [ "$ENV" != "production" ]; then
    echo "Error: Environment must be 'staging' or 'production'"
    exit 1
fi

# Execute the requested command
case "$COMMAND" in
    up)   do_up "$ENV" ;;
    down) do_down "$ENV" ;;
    *)    echo "Error: Unknown command '$COMMAND'"; print_usage; exit 1 ;;
esac
