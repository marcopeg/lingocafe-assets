-include .env

IMAGE ?= marcopeg/lingocafe-assets
VERSION ?= $(shell date +%Y%m%d%H%M%S)
VERSION := $(VERSION)
PORT ?= 4000
CONTAINER ?= lingocafe-assets
UNIVERSAL_PLATFORMS ?= linux/amd64,linux/arm64
CAPROVER ?= npx --yes caprover
CAPROVER_URL := $(subst ",,$(CAPROVER_URL))
CAPROVER_APP ?= lingocafe-assets
CAPROVER_APP := $(subst ",,$(CAPROVER_APP))
CAPROVER_APP_TOKEN := $(subst ",,$(CAPROVER_APP_TOKEN))
CAPROVER_IMAGE ?= $(IMAGE):$(VERSION)
CAPROVER_IMAGE := $(subst ",,$(CAPROVER_IMAGE))

export CAPROVER_URL
export CAPROVER_APP_TOKEN

.PHONY: boot build run run-detached stop logs shell publish publish.nocache deploy.caprover deploy.nocache deploy

boot: run

build:
	docker buildx build --load -t $(IMAGE):latest .

run: build
	docker run --rm --name $(CONTAINER) -p $(PORT):80 $(IMAGE):latest

run-detached: build
	docker run -d --rm --name $(CONTAINER) -p $(PORT):80 $(IMAGE):latest
	@echo "Serving assets at http://localhost:$(PORT)"

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
		-t $(IMAGE):latest \
		-t $(IMAGE):$(VERSION) \
		--push \
		.

publish.nocache:
	@echo "Building version: $(VERSION) without cache"
	docker buildx build --platform $(UNIVERSAL_PLATFORMS) \
		--no-cache \
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

deploy.nocache: publish.nocache deploy.caprover
deploy: publish deploy.caprover
