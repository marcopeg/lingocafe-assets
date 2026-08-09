# LingoCafe Assets

Static asset server for LingoCafe book images.

This repository builds a small Nginx Docker image that serves the contents of
`src/` from `/usr/share/nginx/html`. It is meant to behave like a simple CDN
replacement for immutable public assets.

## Asset Layout

Files under `src/` become public paths at the server root.

Example:

```text
src/dracula/reader.jpg
src/dracula/reader.webp
src/dracula/reader.avif
```

are served as:

```text
/dracula/reader.jpg
/dracula/reader.webp
/dracula/reader.avif
```

Persona avatars are published under immutable, content-addressed paths:

```text
src/personas/<persona-id>/<presentation-id>/avatar-<sha256>.svg
```

The filename hash must match the complete SVG bytes. Applications store the
relative path and prefix it with the configured assets origin, so the same
database content works with local Nginx, the current production host, or a
future CDN.

## Image Negotiation

Extensionless image URLs negotiate by browser `Accept` header:

```text
/dracula/reader
```

Nginx tries the best supported available file in this order:

```text
reader.avif
reader.webp
reader.jpg
```

Negotiated responses include:

```text
Vary: Accept
Cache-Control: public, max-age=31536000, immutable
Access-Control-Allow-Origin: *
X-Content-Type-Options: nosniff
```

Direct file URLs, such as `/dracula/reader.jpg`, are served as normal static
files and do not negotiate.

Missing assets return `404` with `Cache-Control: no-store`.

## Development

Build the local image:

```sh
make build
```

Run it locally:

```sh
make run
```

By default the server is available at:

```text
http://localhost:4000
```

The current persona review URLs are:

```text
http://localhost:4000/personas/mark-carter/mark-carter/avatar-3e58deedc8bf9998baaf3ee8a87f8ba34de45f7eb20182ef01b04d0e544ba48a.svg
http://localhost:4000/personas/mark-carter/marco-conti/avatar-25e296537f4c2e9a8d58d68557481614607a2c66fd05ce4a7c49109fa00af697.svg
http://localhost:4000/personas/sophie-clarke/sophie-clarke/avatar-bfaec2baedb0f65515dc28fa6eb55e096216943a9889fe0b0bd74b8397971958.svg
http://localhost:4000/personas/sophie-clarke/sofia-rinaldi/avatar-a98a9d839f0b118ce04ce36bea74ad4c6c694ee0d251711d2aa6f1e65e550aec.svg
```

Override the port if needed:

```sh
make run PORT=4081
```

## Publishing

Publish a multi-architecture image to Docker Hub:

```sh
make publish
```

The image is tagged as both `latest` and a timestamp version.

## Deployment

Build and push the multi-architecture image locally, deploy its immutable
timestamp tag to CapRover, and verify the public deployment marker:

```sh
make deploy.mac
```

`make deploy` is an alias for the same verified local flow. Neither command
creates a Git tag. To build and deploy through GitHub Actions instead, run:

```sh
make deploy.github
```

Both flows wait 30 seconds after starting the deployment, then poll
`https://assets.lingocafe.app/deployment-<timestamp>.txt` every 10 seconds for
up to five minutes. They succeed only when the endpoint returns HTTP 200 with
the exact timestamp. Automation that performs its own rollout verification can
set `SKIP_DEPLOYMENT_VERIFY=1`.
