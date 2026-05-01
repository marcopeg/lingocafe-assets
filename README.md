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
