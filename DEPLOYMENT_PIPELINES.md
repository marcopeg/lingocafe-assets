# Next.js Deployment Pipelines

This document explains how to replicate this repository's two verified CapRover
deployment paths in a Next.js project.

Both paths use the same release contract:

1. Read one application version.
2. Bake it into a Docker image for both target architectures.
3. Publish an immutable version tag.
4. Ask CapRover to deploy that exact tag.
5. Verify the public application reports the same version.

| Path | Image build and push | Deployment trigger |
| --- | --- | --- |
| `make deploy.mac` | developer machine | local CapRover CLI |
| `make deploy.github` | GitHub Actions | a Git tag pushed by Make |

The deployment request must always use an immutable version tag, never
`latest`. Updating `latest` is optional and must not determine what CapRover
runs.

## Version Contract

For the Next.js project, `package.json` is the version source of truth. Bump it
for every deployment, for example from `1.8.0` to `1.8.1`.

Use these related values:

```text
package.json version:  1.8.0
Git tag:               v1.8.0
Docker image tag:      1.8.0
version-route body:    1.8.0
```

The `v` prefix is a Git tag convention only. The runtime response should equal
the package version exactly.

Capture the version once in the Makefile, so sub-makes cannot recompute it:

```make
APP_VERSION ?= $(shell node -p "require('./package.json').version")
APP_VERSION := $(APP_VERSION)
GIT_TAG ?= v$(APP_VERSION)

IMAGE ?= docker.io/example/my-next-app
IMAGE_TAG ?= $(APP_VERSION)
CAPROVER_IMAGE ?= $(IMAGE):$(IMAGE_TAG)
```

The GitHub workflow must verify that the checked-out `package.json` version
equals the version derived from the Git tag. This prevents a mismatched manual
tag from deploying an ambiguous release.

## Docker Image

Bake `APP_VERSION` into the image. The deployed container must not query a
mutable source to decide its release identity.

```dockerfile
FROM node:22-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .

ARG APP_VERSION
ENV APP_VERSION=$APP_VERSION
RUN npm run build

FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

ARG APP_VERSION
ENV APP_VERSION=$APP_VERSION

# Requires output: 'standalone' in next.config.js.
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public

EXPOSE 3000
CMD ["node", "server.js"]
```

Adjust package-manager and copy commands to the project. What matters is that
the version presented to clients comes from the same image CapRover receives.

## Public Version Route

The final assertion must go through the real production hostname. It should not
rely on a container health check or on CapRover accepting the deploy request.

With the App Router, create `src/app/api/version/route.ts`:

```ts
export const dynamic = 'force-dynamic';

export function GET() {
  const version = process.env.APP_VERSION;

  if (!version) {
    return new Response('version unavailable\n', { status: 500 });
  }

  return new Response(version + '\n', {
    headers: {
      'content-type': 'text/plain; charset=utf-8',
      'cache-control': 'no-store',
    },
  });
}
```

The check passes only when `GET https://app.example.com/api/version` returns
HTTP `200` and its body, after removing its final newline, equals
`APP_VERSION`. `no-store` prevents a CDN or proxy cache from producing a false
positive.

For the Pages Router, implement the equivalent handler in
`pages/api/version.ts`. A fully static Next.js export cannot have an API route;
instead generate a versioned static file during the Docker build and verify it.

## Shared Make Targets

Both paths should call the same `publish`, `deploy.caprover`, and
`verify.deployment` targets.

```make
UNIVERSAL_PLATFORMS ?= linux/amd64,linux/arm64
DEPLOYMENT_URL ?= https://app.example.com/api/version
DEPLOYMENT_VERIFY_INITIAL_WAIT ?= 30
DEPLOYMENT_VERIFY_INTERVAL ?= 10
DEPLOYMENT_VERIFY_ATTEMPTS ?= 30

publish:
	docker buildx build --platform $(UNIVERSAL_PLATFORMS) \
		--build-arg APP_VERSION=$(APP_VERSION) \
		-t $(IMAGE):$(IMAGE_TAG) \
		-t $(IMAGE):latest \
		--push .

deploy.caprover:
	npx --yes caprover deploy \
		--caproverUrl "$$CAPROVER_URL" \
		--caproverApp "$$CAPROVER_APP" \
		--imageName "$(CAPROVER_IMAGE)" \
		--appToken "$$CAPROVER_APP_TOKEN"

verify.deployment:
	@expected="$(APP_VERSION)"; \
	url="$(DEPLOYMENT_URL)"; \
	echo "Waiting $(DEPLOYMENT_VERIFY_INITIAL_WAIT)s before checking $$url"; \
	sleep $(DEPLOYMENT_VERIFY_INITIAL_WAIT); \
	for attempt in $$(seq 1 $(DEPLOYMENT_VERIFY_ATTEMPTS)); do \
		tmp=$$(mktemp); \
		status=$$(curl --silent --show-error --location \
			--max-time $(DEPLOYMENT_VERIFY_INTERVAL) \
			--output "$$tmp" --write-out '%{http_code}' \
			"$$url?verify=$$expected-$$attempt" || true); \
		body=$$(tr -d '\r\n' < "$$tmp"); rm -f "$$tmp"; \
		if [ "$$status" = 200 ] && [ "$$body" = "$$expected" ]; then \
			echo "Verified production version $$expected"; exit 0; \
		fi; \
		echo "Attempt $$attempt/$(DEPLOYMENT_VERIFY_ATTEMPTS): HTTP $${status:-000}, version not ready"; \
		sleep $(DEPLOYMENT_VERIFY_INTERVAL); \
	done; \
	echo "Production did not report version $$expected"; exit 1
```

The verifier records both status and body. That distinguishes `404`, `500`,
connection errors, and a stale version in the terminal output.

## Pipeline A: Local Build, Push, Deploy, Verify

The local path builds on the developer machine but publishes a multi-platform
manifest so the CapRover host pulls the compatible platform.

```make
deploy.mac: publish
	@make deploy.caprover APP_VERSION="$(APP_VERSION)"
	@make verify.deployment APP_VERSION="$(APP_VERSION)"

deploy: deploy.mac
```

Run:

```sh
make deploy.mac
```

The expected sequence is:

1. Buildx creates `linux/amd64` and `linux/arm64`.
2. The registry receives `IMAGE:APP_VERSION` and optionally `IMAGE:latest`.
3. The CapRover CLI requests `IMAGE:APP_VERSION`.
4. Make waits 30 seconds, then polls every 10 seconds for up to five minutes.
5. The command succeeds only when production returns `APP_VERSION`.

Local CapRover settings belong in an ignored `.env` file:

```dotenv
CAPROVER_URL=https://captain.example.com
CAPROVER_APP=my-next-app
CAPROVER_APP_TOKEN=app-scoped-deploy-token
```

Commit `.env.example` with placeholders only. An app-scoped CapRover token can
start a deployment, but it does not retrieve detailed rollout logs. This is why
the public version check is required.

## Pipeline B: GitHub Build, Push, Deploy, Verify

The GitHub path creates and pushes a tag based on the package version. The
workflow builds and deploys the same immutable image; the local Make process
then checks the public route.

```make
deploy.github:
	@tag="$(GIT_TAG)"; \
	if git rev-parse -q --verify "refs/tags/$$tag" >/dev/null; then \
		echo "Tag $$tag already exists; bump package.json version"; exit 1; \
	fi; \
	git tag -a "$$tag" -m "Deploy $$tag"; \
	git push origin "$$tag"; \
	make verify.deployment APP_VERSION="$(APP_VERSION)"
```

Release sequence:

1. Update `package.json` and its lockfile.
2. Commit and push the version change.
3. Run `make deploy.github` from that exact commit.
4. The `vVERSION` tag triggers GitHub Actions.
5. The Make command verifies the deployed public version.

Use a tag-only workflow trigger:

```yaml
on:
  push:
    tags:
      - 'v*'
```

Set the image name at workflow scope, then use an explicit step output for the
version derived from the Git tag:

```yaml
env:
  IMAGE: docker.io/example/my-next-app

- uses: actions/checkout@v4

- name: Derive and validate app version
  id: version
  run: |
    echo "app_version=${GITHUB_REF_NAME#v}" >> "$GITHUB_OUTPUT"
    test "$(node -p "require('./package.json').version")" = "${GITHUB_REF_NAME#v}"

- uses: docker/setup-qemu-action@v3
- uses: docker/setup-buildx-action@v3

- uses: docker/login-action@v3
  with:
    username: ${{ secrets.DOCKERHUB_USERNAME }}
    password: ${{ secrets.DOCKERHUB_TOKEN }}

- uses: docker/build-push-action@v6
  with:
    context: .
    platforms: linux/amd64,linux/arm64
    build-args: |
      APP_VERSION=${{ steps.version.outputs.app_version }}
    push: true
    tags: |
      ${{ env.IMAGE }}:${{ steps.version.outputs.app_version }}
      ${{ env.IMAGE }}:latest

- name: Deploy immutable image with CapRover
  env:
    CAPROVER_URL: ${{ secrets.CAPROVER_URL }}
    CAPROVER_APP: ${{ secrets.CAPROVER_APP }}
    CAPROVER_APP_TOKEN: ${{ secrets.CAPROVER_APP_TOKEN }}
  run: |
    npx --yes caprover deploy \
      --caproverUrl "$CAPROVER_URL" \
      --caproverApp "$CAPROVER_APP" \
      --imageName "${{ env.IMAGE }}:${{ steps.version.outputs.app_version }}" \
      --appToken "$CAPROVER_APP_TOKEN"
```

Configure these GitHub Actions secrets:

```text
DOCKERHUB_USERNAME
DOCKERHUB_TOKEN
CAPROVER_URL
CAPROVER_APP
CAPROVER_APP_TOKEN
```

A successful Action proves the image was built and pushed, and that CapRover
accepted the request. It does not alone prove the replacement container serves
traffic. The public route is the final proof.

## Operational Requirements

- Build `linux/amd64` and `linux/arm64` in both paths. A Mac-local run alone
  does not prove the VPS platform can start the image.
- Deploy the immutable `IMAGE:APP_VERSION`, never `latest`.
- Keep verification bounded: 30 seconds initial delay, then 30 attempts at
  10-second intervals is a practical default.
- Use a cache-busting query parameter for verification requests.
- Preserve failed tags and image versions while diagnosing an incident; they
  identify the exact artifact CapRover was asked to run.
- An external deployment service may skip local polling only when it performs
  the equivalent public HTTP-status and exact-version assertion.

## Acceptance Criteria

Each deployment path is working only when:

1. The registry has an `amd64` and `arm64` manifest for the immutable image.
2. CapRover was asked to deploy that immutable image.
3. The public version route returns HTTP `200`.
4. The route body equals the release's `package.json` version.

The fourth condition is decisive: it verifies the externally reachable service,
not merely a successful build, registry push, or accepted deployment request.
