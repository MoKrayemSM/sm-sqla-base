# sm-sqla-base — build & verify the shared SQL Anywhere 17 client image.

IMAGE        ?= sm-sqla-base
TAG          ?= 17
SQLA_TARBALL ?= sqla17_client_linux_x86x64.tar.gz
# Expected sha256 of the canonical tarball (all repos carry the identical file).
SQLA_SHA256  ?= 097c870c29dc05b597879092e3911359779b2ad1b617ffaa8fa386148f6688d4

.PHONY: help check build verify shell push clean

help:
	@echo "Targets:"
	@echo "  make check    - verify the tarball is present and checksum matches"
	@echo "  make build    - build $(IMAGE):$(TAG)"
	@echo "  make verify   - run the image to list the SQLA client payload"
	@echo "  make shell    - open a shell in the image to poke around"
	@echo "  make push     - push to the configured registry (set REGISTRY=...)"

check:
	@test -f "$(SQLA_TARBALL)" || { echo "ERROR: $(SQLA_TARBALL) not found. See README (obtain from internal artifact store)."; exit 1; }
	@echo "$(SQLA_SHA256)  $(SQLA_TARBALL)" | shasum -a 256 -c - \
		|| { echo "ERROR: checksum mismatch — tarball does not match the pinned SQLA 17 client."; exit 1; }
	@echo "OK: $(SQLA_TARBALL) present and checksum verified."

build: check
	docker build --build-arg SQLA_TARBALL=$(SQLA_TARBALL) -t $(IMAGE):$(TAG) .

verify:
	docker run --rm $(IMAGE):$(TAG)

shell:
	docker run --rm -it --entrypoint sh $(IMAGE):$(TAG)

push:
	@test -n "$(REGISTRY)" || { echo "ERROR: set REGISTRY=your.registry/path"; exit 1; }
	docker tag $(IMAGE):$(TAG) $(REGISTRY)/$(IMAGE):$(TAG)
	docker push $(REGISTRY)/$(IMAGE):$(TAG)

clean:
	-docker rmi $(IMAGE):$(TAG)
