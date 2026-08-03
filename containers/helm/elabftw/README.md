# eLabFTW Helm chart

A Helm chart to deploy [eLabFTW](https://www.elabftw.net) on Kubernetes.

It is modelled on the official `docker-compose` configuration
(fetched from `https://get.elabftw.net/?config`, see also
[`containers/elabimg/README.md`](../../elabimg/README.md)) and deploys:

* **web** – the main eLabFTW container (`elabftw/elabimg`): nginx + php-fpm +
  chronos + invoker, managed by s6-overlay.
* **mysql** – an optional bundled MySQL 8.4 database (`StatefulSet`).
* **redis** – an optional bundled Redis session store (`StatefulSet`),
  required when running more than one web replica.

## TL;DR

```bash
# from the repository root
helm install elabftw containers/helm/elabftw \
  --namespace elabftw --create-namespace \
  --set secrets.secretKey="$(docker run --rm -t --entrypoint '/bin/sh' elabftw/elabimg \
      -c "php -d memory_limit=10M -d open_basedir='' bin/init tools:genkey" | tr -d '\r')" \
  --set secrets.dbPassword='a-strong-password' \
  --set mysql.auth.password='a-strong-password' \
  --set mysql.auth.rootPassword='another-strong-password' \
  --set web.env.SITE_URL='https://elab.example.org'
```

> `secrets.dbPassword` and `mysql.auth.password` **must** be identical, exactly
> like `DB_PASSWORD` and `MYSQL_PASSWORD` in the compose file.

## Configuration mapping (compose → chart)

| docker-compose | chart value |
| --- | --- |
| `web.image` | `image.repository` / `image.tag` |
| `web.environment.DB_*` | `web.env.DB_*` (host auto-wired to bundled mysql) |
| `web.environment.SECRET_KEY` | `secrets.secretKey` |
| `web.environment.DB_PASSWORD` | `secrets.dbPassword` |
| `web.environment.SITE_URL` | `web.env.SITE_URL` |
| `web.environment.DISABLE_HTTPS` | `web.env.DISABLE_HTTPS` |
| `web.cap_drop` / `cap_add` | `securityContext.capabilities` |
| `web.ports 443:443` | `service` + `ingress` |
| `web.volumes /elabftw/uploads` | `persistence.uploads` |
| `web.volumes /elabftw/exports` | `persistence.exports` |
| `mysql.*` | `mysql.*` |
| `redis.*` | `redis.*` |
| healthcheck `/healthcheck` | `probes.*` |

All optional environment variables from the compose file can be set under
`web.env.*` or via `web.extraEnv` / `web.extraEnvFrom`.

## Secrets

By default the chart creates a `Secret` from `secrets.*`. For production, manage
the secret yourself and reference it:

```yaml
secrets:
  create: false
  existingSecret: my-elabftw-secret   # must contain DB_PASSWORD, SECRET_KEY, ...
```

## Ingress

The ingress is **opt-in and off by default**. When `ingress.enabled=true`, the
chart creates an nginx `Ingress` (`ingressClassName` defaults to `nginx`), and
you **must** provide `ingress.hosts` explicitly — there is no implicit host
derivation. Rendering fails with a clear error if hosts are missing.

```yaml
ingress:
  enabled: true
  # className: nginx   # optional, defaults to nginx
  hosts:
    - host: elab.example.org
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: elabftw-tls
      hosts:
        - elab.example.org
```

## TLS termination

**Default: TLS terminated at the ingress.** `web.env.DISABLE_HTTPS` defaults to
`"true"`, so elabimg serves plain HTTP on port 443 and the nginx Ingress
terminates TLS (configure `ingress.tls`). The probe scheme switches to HTTP
automatically. No `backend-protocol` annotation is needed.

To have **elabimg serve HTTPS end-to-end** instead, set
`web.env.DISABLE_HTTPS=false`, mount certificates via `web.extraVolumes` /
`web.extraVolumeMounts` at `/ssl`, set `web.env.ENABLE_LETSENCRYPT` accordingly,
and add `nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"` to
`ingress.annotations` so nginx talks HTTPS to the backend.

## High availability

To run multiple web replicas you must share PHP sessions via Redis:

```yaml
replicaCount: 3
redis:
  enabled: true
```

`autoscaling.enabled=true` (HPA) has the same requirement.

Note that the default `persistence.uploads` PVC uses `ReadWriteOnce`. For
multiple replicas across nodes you need a `ReadWriteMany` storage class (NFS,
CephFS, etc.) or object storage (S3, via `secrets.awsAccessKey`/`awsSecretKey`).

## Data retention on uninstall

To avoid accidental data loss, the **uploads PVC is annotated with
`helm.sh/resource-policy: keep`**, so `helm uninstall` does **not** delete it.
This is controlled by `persistence.uploads.retain` (default `true`). The exports
PVC defaults to `retain: false` since exports are regenerable.

```yaml
persistence:
  uploads:
    retain: true    # kept on helm uninstall (default)
  exports:
    retain: false   # deleted on helm uninstall (default)
```

The bundled **MySQL data PVC also survives uninstall**: it is created from the
StatefulSet's `volumeClaimTemplates`, and Kubernetes never deletes those
automatically when the StatefulSet is removed.

Because these are kept, a subsequent `helm install` with the same release name
reuses the existing data. To actually remove kept volumes, delete them by hand:

```bash
kubectl delete pvc -n elabftw elabftw-uploads
kubectl delete pvc -n elabftw data-elabftw-mysql-0   # bundled mysql
```

## Database initialization

The schema is installed and migrated automatically by the **elabimg image's own
entrypoint**, driven by two env vars the chart sets from the `dbInit` block:

```yaml
dbInit:
  init: true      # -> AUTO_DB_INIT=true   (db:install on start, idempotent)
  migrate: true   # -> AUTO_DB_UPDATE=true (db:update on start)
```

Both default to `true`. The entrypoint runs these **after** it templates the PHP
config (`open_basedir`, `memory_limit`, etc.), which is why this works where a
standalone `bin/init` call does not — running `bin/init` directly bypasses that
templating and fails with `open_basedir restriction ... (%OPEN_BASEDIR%)`.

`db:install` is idempotent and never wipes existing data.

Follow progress in the web pod logs:

```bash
kubectl logs -n elabftw deploy/elabftw -c web
```

Multiple replicas: these commands run on every web pod. The default rollout
(`maxSurge:1`, `maxUnavailable:0`) starts pods one at a time, so migrations don't
overlap. If you prefer to manage the schema yourself, disable both and run it
manually:

```yaml
dbInit:
  init: false
  migrate: false
```

```bash
kubectl exec -n elabftw deploy/elabftw -c web -- bin/init db:install
```

## Development

For a local dev deployment aligned with the `DEV_MODE` documented in
[`containers/elabimg/README.md`](../../elabimg/README.md):

```bash
helm install elab-dev ./containers/helm/elabftw \
  --set secrets.secretKey='<generated-key>' \
  --set web.env.DEV_MODE=true \
  --set web.env.SITE_URL=https://localhost:8443

kubectl port-forward svc/elab-dev-elabftw 8443:443
```

Schema install/upgrade is handled automatically by the elabimg entrypoint
(`dbInit.init` / `dbInit.migrate`, both default `true`), so no manual step is
needed. See [Database initialization](#database-initialization).

## Tests

The chart is covered by [`helm-unittest`](https://github.com/helm-unittest/helm-unittest)
suites under `tests/`, plus `helm lint`. CI runs these on every pull request
(`.github/workflows/helm.yml`).

Run them locally:

```bash
# one-time: install the plugin
helm plugin install https://github.com/helm-unittest/helm-unittest

helm lint containers/helm/elabftw
helm unittest containers/helm/elabftw
```

The suites assert the key behaviors: image/tag, `NET_BIND_SERVICE` capability,
probe scheme following `DISABLE_HTTPS`, MySQL wait init-container, `DB_HOST` and
Redis wiring, `AUTO_DB_INIT`/`AUTO_DB_UPDATE` from `dbInit`, the ingress
requiring explicit hosts and defaulting to the `nginx` class, and the uploads
PVC `helm.sh/resource-policy: keep` retention.

To eyeball rendered output:

```bash
helm template rel containers/helm/elabftw --set secrets.secretKey=abc | less
```
