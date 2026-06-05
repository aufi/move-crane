# WordPress Application (stateful)

A comprehensive multi-tier Kubernetes application that deploys a full WordPress installation with MySQL database backend, persistent storage, and automated installation.

This setup is based on Kubernetes tutorial https://kubernetes.io/docs/tutorials/stateful-application/mysql-wordpress-persistent-volume/, but it is significantly extended.

## Application Description

This application demonstrates a stateful, production-like WordPress deployment consisting of multiple Kubernetes resources defined across several manifest files:

### MySQL Database (mysql-deployment.yaml)

#### Service
- **Name**: `wordpress-mysql`
- **Port**: 3306
- **Selector**: Routes traffic to pods with labels `app: wordpress`, `tier: mysql`
- **Type**: ClusterIP (internal)

#### PersistentVolumeClaim
- **Name**: `mysql-pv-claim`
- **Storage**: 1Gi
- **Access Mode**: ReadWriteOnce
- **Purpose**: Persistent storage for MySQL database files at `/var/lib/mysql`

#### Deployment
- **Name**: `wordpress-mysql`
- **Container**: MySQL 8.0
- **Strategy**: Recreate (ensures clean shutdown/startup of database)
- **Volume Mount**: Persistent storage for database data

### WordPress Frontend (wordpress-deployment.yaml)

#### Service
- **Name**: `wordpress`
- **Type**: LoadBalancer
- **Port**: 80
- **Selector**: Routes traffic to pods with labels `app: wordpress`, `tier: frontend`

#### PersistentVolumeClaim
- **Name**: `wordpress-pv-claim`
- **Storage**: 1Gi
- **Access Mode**: ReadWriteOnce
- **Purpose**: Persistent storage for WordPress files, themes, plugins, and uploads at `/var/www/html`

#### Deployment
- **Name**: `wordpress`
- **Strategy**: Recreate (ensures clean shutdown/startup with persistent volumes)
- **Containers**: Multi-container pod with WordPress and NGINX. Both containers share the same persistent volume for WordPress files, enabling NGINX to serve static assets while forwarding PHP requests to WordPress via FastCGI.

##### WordPress Container
- **Image**: wordpress:6-fpm-alpine (PHP-FPM variant)
- **Port**: 9000 (FastCGI)
- **Volume Mount**: Shared WordPress files storage

##### NGINX Container
- **Image**: nginx:alpine
- **Port**: 80 (HTTP)
- **Purpose**: Web server that serves static files and proxies PHP requests to WordPress FPM container
- **Volume Mounts**:
  - WordPress files (read-only)
  - NGINX configuration from ConfigMap

### NGINX Configuration (nginx-config.yaml)

#### ConfigMap
- **Name**: `nginx-config`
- **Purpose**: Custom NGINX configuration for WordPress
- **Configuration**:
  - Serves static files directly
  - Proxies PHP requests to FastCGI on port 9000 (WordPress container)
  - Handles WordPress permalinks with proper URL rewriting

### WordPress Installation Job (wordpress-install-job.yaml)

#### Job
- **Name**: `wordpress-install`
- **Container**: wordpress:cli-2 (WordPress CLI)
- **Backoff Limit**: 4 retries
- **Purpose**: Automated, idempotent WordPress installation and setup
- **Process**:
  1. Waits for MySQL database to be ready (up to 5 minutes)
  2. Creates `wp-config.php` if missing
  3. Installs WordPress if not already installed (idempotent)
  4. Creates a sample post with random content

### Secrets Management (kustomization.yaml)

#### Secret Generator
- **Name**: `wordpress-secrets`
- **Source**: `.env` file (generated during deployment)
- **Generated Passwords**:
  - `MYSQL_ROOT_PASSWORD`: MySQL root password
  - `MYSQL_WORDPRESS_PASSWORD`: WordPress database user password
  - `WORDPRESS_ADMIN_PASSWORD`: WordPress admin user password

## Deployment

To deploy the application to your Kubernetes cluster, run:

```bash
./deploy.sh
```

The `deploy.sh` script will:
1. Generate random passwords in `.env` file if it doesn't exist
2. Apply all resources using Kustomize
3. Wait for deployments to be ready and Wordpress installed

### Accessing the Application

To access the WordPress application, get the service endpoint and reach it depending on your local clusters setup.

```bash
kubectl get service wordpress
```

#### Examples

Using Minikube:
```bash
minikube service wordpress
```

Using port-forwarding (both minikube and kind)
```bash
kubectl port-forward service/wordpress 8080:80
```
Then visit `http://127.0.0.1:8080` in your browser.

To access Wordpress admin panel, open `/wp-admin/` path using `admin` username and `WORDPRESS_ADMIN_PASSWORD` from local `.env` file.

## Validation

To validate that the WordPress application is running correctly, use the `validate.sh` script:

```bash
./validate.sh
```

The validation script will:
1. Start a `kubectl port-forward` to the WordPress service (default port 18080)
2. Perform an HTTP request to the WordPress homepage, check HTTP status
3. Verify HTML content to contain expected text from the sample post
4. Clean up the port-forward process

### Advanced Validation (stateful)

To validate a **specific** WordPress deployment by checking the exact sample post seed ID generated during installation:

```bash
# Extract the seed ID from the wordpress-install job logs
WORDPRESS_SEED_ID=$(kubectl logs job/wordpress-install | grep WORDPRESS_SEED_ID= | cut -d= -f2)

# Run validation with the specific seed ID
WORDPRESS_SEED_ID=$WORDPRESS_SEED_ID ./validate.sh
```

This ensures you're validating the exact WordPress deployment instance.

## Cleanup

To remove the application from your cluster, run:

```bash
./destroy.sh
```

**Note**: Depending on your storage provisioner's reclaim policy, the persistent volumes may be retained or deleted. Check your PV reclaim policy if you need to preserve data.



### PVC details and troubleshooting

Data on PV make this application a stateful deployment. If needed check PVC and PV status:
```bash
kubectl get pvc
kubectl get pv
kubectl describe pvc mysql-pv-claim
kubectl describe pvc wordpress-pv-claim
```

Ensure your cluster has a storage provisioner or manually provision PVs.
