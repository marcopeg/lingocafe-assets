# GitHub Actions deployment secrets

The tag-triggered deployment workflow uses repository-level GitHub Actions
secrets. The following CapRover secrets are managed from the local `.env` file:

- `CAPROVER_URL`
- `CAPROVER_APP`
- `CAPROVER_APP_TOKEN`

The workflow also requires Docker Hub credentials:

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

## Check or update secrets

In GitHub, open the [repository Actions secrets page](https://github.com/marcopeg/lingocafe-assets/settings/secrets/actions).
The **Repository secrets** list shows secret names and their last update time,
but GitHub never displays an existing secret value.

To replace a value, select the secret, choose **Update**, enter the replacement,
and save. A replacement is used by subsequent workflow runs only; it does not
change a workflow run that is already in progress.

## Create a Docker Hub access token

1. Sign in to [Docker Hub](https://hub.docker.com/).
2. Open **My Account** → **Personal access tokens**.
3. Create a token with read/write access to the `marcopeg/lingocafe-assets`
   repository. Name it for this GitHub Actions deployment.
4. Copy the token immediately; Docker Hub will not show it again.
5. On the GitHub Actions secrets page, set `DOCKERHUB_USERNAME` to the Docker
   Hub account name and `DOCKERHUB_TOKEN` to the generated token.

Rotate the Docker Hub token by creating a replacement token, updating
`DOCKERHUB_TOKEN` in GitHub, verifying a deployment, then revoking the old
token in Docker Hub.

## Trigger a deployment manually

From a clean checkout on `main`, run:

```sh
make deploy.github
```

It creates and pushes a timestamp tag in `YYYYMMDDHHMMSS` format. Pushing that
tag triggers the workflow. To choose the timestamp explicitly, use:

```sh
make deploy.github VERSION=20260809153045
```

The workflow publishes `marcopeg/lingocafe-assets:<timestamp>` and updates
`marcopeg/lingocafe-assets:latest`, then deploys the immutable timestamp tag.
