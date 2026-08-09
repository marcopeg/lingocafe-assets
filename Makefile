-include .env

IMAGE ?= marcopeg/lingocafe-assets
VERSION ?= $(shell date +%Y%m%d%H%M%S)
VERSION := $(VERSION)
PORT ?= 4000
CONTAINER ?= lingocafe-assets
SRC_DIR ?= $(CURDIR)/src
HTML_ROOT ?= /usr/share/nginx/html
NGINX_DEV_CONF ?= $(CURDIR)/nginx.dev.conf
UNIVERSAL_PLATFORMS ?= linux/amd64,linux/arm64
CAPROVER ?= npx --yes caprover
CAPROVER_URL := $(subst ",,$(CAPROVER_URL))
CAPROVER_APP ?= lingocafe-assets
CAPROVER_APP := $(subst ",,$(CAPROVER_APP))
CAPROVER_APP_TOKEN := $(subst ",,$(CAPROVER_APP_TOKEN))
CAPROVER_IMAGE ?= $(IMAGE):$(VERSION)
CAPROVER_IMAGE := $(subst ",,$(CAPROVER_IMAGE))
GITHUB_REPO ?= marcopeg/lingocafe-assets
DEPLOYMENT_URL ?= https://assets.lingocafe.app
DEPLOYMENT_VERIFY_INITIAL_WAIT ?= 30
DEPLOYMENT_VERIFY_INTERVAL ?= 10
DEPLOYMENT_VERIFY_ATTEMPTS ?= 30
SKIP_DEPLOYMENT_VERIFY ?= 0

export CAPROVER_URL
export CAPROVER_APP_TOKEN

.PHONY: boot build run run-detached stop logs shell publish publish.nocache deploy.caprover deploy.nocache deploy deploy.mac deploy.github verify.deployment verify.deployment.maybe

boot: run

build:
	docker buildx build --load \
		--build-arg DEPLOYMENT_ID=$(VERSION) \
		-t $(IMAGE):latest \
		.

run: build
	docker run --rm --name $(CONTAINER) -p $(PORT):80 \
		-v "$(SRC_DIR):$(HTML_ROOT):ro" \
		-v "$(NGINX_DEV_CONF):/etc/nginx/nginx.conf:ro" \
		$(IMAGE):latest

run-detached: build
	docker run -d --rm --name $(CONTAINER) -p $(PORT):80 \
		-v "$(SRC_DIR):$(HTML_ROOT):ro" \
		-v "$(NGINX_DEV_CONF):/etc/nginx/nginx.conf:ro" \
		$(IMAGE):latest
	@echo "Serving live assets at http://localhost:$(PORT)"

stop:
	-docker stop $(CONTAINER)

logs:
	docker logs -f $(CONTAINER)

shell:
	docker run --rm -it --entrypoint /bin/sh $(IMAGE):latest

###
### Publish to DockerHUB
###
publish:
	@echo "Building version: $(VERSION)"
	docker buildx build --platform $(UNIVERSAL_PLATFORMS) \
		--build-arg DEPLOYMENT_ID=$(VERSION) \
		-t $(IMAGE):latest \
		-t $(IMAGE):$(VERSION) \
		--push \
		.

publish.nocache:
	@echo "Building version: $(VERSION) without cache"
	docker buildx build --platform $(UNIVERSAL_PLATFORMS) \
		--no-cache \
		--build-arg DEPLOYMENT_ID=$(VERSION) \
		-t $(IMAGE):latest \
		-t $(IMAGE):$(VERSION) \
		--push \
		.

deploy.caprover:
	@if [ -z "$$CAPROVER_URL" ]; then \
		echo "CAPROVER_URL is required. Add it to .env or pass CAPROVER_URL=https://captain.example.com"; \
		exit 1; \
	fi
	@if [ -z "$$CAPROVER_APP_TOKEN" ]; then \
		echo "CAPROVER_APP_TOKEN is required. Add it to .env or pass it in the environment"; \
		exit 1; \
	fi
	@echo "Deploying $(CAPROVER_IMAGE) to CapRover app $(CAPROVER_APP)"
	@$(CAPROVER) deploy \
		--caproverUrl "$$CAPROVER_URL" \
		--caproverApp "$(CAPROVER_APP)" \
		--imageName "$(CAPROVER_IMAGE)" \
		--appToken "$$CAPROVER_APP_TOKEN"

deploy.mac: publish
	@make deploy.caprover VERSION="$(VERSION)"
	@make verify.deployment.maybe VERSION="$(VERSION)"

deploy.nocache: publish.nocache
	@make deploy.caprover VERSION="$(VERSION)"
	@make verify.deployment.maybe VERSION="$(VERSION)"

deploy: deploy.mac

###
### Deploy through GitHub Actions
###
deploy.github:
	@tag="$(VERSION)"; \
	if ! printf '%s' "$$tag" | grep -Eq '^20[0-9]{12}$$'; then \
		echo "VERSION must be a timestamp in YYYYMMDDHHMMSS format (got: $$tag)"; \
		exit 1; \
	fi; \
	if git rev-parse -q --verify "refs/tags/$$tag" >/dev/null; then \
		echo "Tag $$tag already exists; choose a new VERSION"; \
		exit 1; \
	fi; \
	git tag -a "$$tag" -m "Deploy $$tag"; \
	git push origin "$$tag"; \
	echo "Deployment started: https://github.com/$(GITHUB_REPO)/actions"; \
	make verify.deployment.maybe VERSION="$$tag"

verify.deployment.maybe:
	@if [ "$(SKIP_DEPLOYMENT_VERIFY)" = "1" ]; then \
		echo "Skipping local deployment verification; the caller must verify the rollout"; \
	else \
		make verify.deployment VERSION="$(VERSION)"; \
	fi

verify.deployment:
	@base_url="$(DEPLOYMENT_URL)"; \
	marker_url="$${base_url%/}/deployment-$(VERSION).txt"; \
	marker_file="$$(mktemp)"; \
	trap 'rm -f "$$marker_file"' EXIT; \
	echo "Waiting $(DEPLOYMENT_VERIFY_INITIAL_WAIT)s before verifying $$marker_url"; \
	sleep $(DEPLOYMENT_VERIFY_INITIAL_WAIT); \
	attempt=1; \
	while [ $$attempt -le $(DEPLOYMENT_VERIFY_ATTEMPTS) ]; do \
		: > "$$marker_file"; \
		http_code="$$(curl --silent --show-error --location \
			--max-time $(DEPLOYMENT_VERIFY_INTERVAL) \
			--output "$$marker_file" \
			--write-out '%{http_code}' \
			"$$marker_url?verify=$(VERSION)-$$attempt" || true)"; \
		marker="$$(tr -d '\r\n' < "$$marker_file")"; \
		if [ "$$http_code" = "200" ] && [ "$$marker" = "$(VERSION)" ]; then \
			echo "Verified deployment $(VERSION): $$marker_url"; \
			exit 0; \
		fi; \
		echo "Attempt $$attempt/$(DEPLOYMENT_VERIFY_ATTEMPTS): marker not ready (HTTP $${http_code:-000})"; \
		attempt=$$((attempt + 1)); \
		sleep $(DEPLOYMENT_VERIFY_INTERVAL); \
	done; \
	echo "Deployment verification failed after $(DEPLOYMENT_VERIFY_ATTEMPTS) attempts: $$marker_url"; \
	exit 1
