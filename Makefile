IMAGE ?= marcopeg/lingocafe-assets
VERSION ?= $(shell date +%Y%m%d%H%M%S)
PORT ?= 4000
CONTAINER ?= lingocafe-assets

.PHONY: build run run-detached stop logs shell publish

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
	docker buildx build --platform linux/amd64,linux/arm64 \
		-t $(IMAGE):latest \
		-t $(IMAGE):$(VERSION) \
		--push \
		.
