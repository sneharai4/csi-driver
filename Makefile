NAME = csi-driver
REPO_NAME ?= hpe/csi-driver
VERSION = v0.3.0-beta

# golangci-lint allows us to have a single target that runs multiple linters in
# the same fashion.  This variable controls which linters are used.
LINTER_FLAGS = --disable-all --enable=vet --enable=vetshadow --enable=golint --enable=ineffassign --enable=goconst --enable=deadcode --enable=dupl --enable=varcheck --enable=gocyclo --enable=misspell

# Our target binary is for Linux.  To build an exec for your local (non-linux)
# machine, use go build directly.
ifndef GOOS
	GOOS = linux
endif

GOENV = PATH=$$PATH:$(GOPATH)/bin

build: check-env clean compile image push

all: check-env clean tools lint compile image push

.PHONY: help
help:
	@echo "Targets:"
	@echo "    tools    - Download and install go tooling required to build."
	@echo "    vendor   - Download dependencies (go mod vendor)"
	@echo "    lint     - Static analysis of source code.  Note that this must pass in order to build."
	@echo "    clean    - Remove build artifacts."
	@echo "    compile  - Compiles the source code."
	@echo "    test     - Run unit tests."
	@echo "    image    - Build csi driver image and create a local docker image.  Errors are ignored."
	@echo "    push     - Push csi driver image to artifactory."
	@echo "    all      - Clean, lint, build, test, and push image."

.PHONY: check-env
check-env:
ifndef CONTAINER_REGISTRY
	$(error CONTAINER_REGISTRY is undefined)
endif

.PHONY: tools
tools:
	@echo "Get golangci-lint"
	@go get -u github.com/golangci/golangci-lint/cmd/golangci-lint

vendor:
	@go mod vendor

.PHONY: lint
lint:
	@echo "Running lint"
	export $(GOENV) && golangci-lint run $(LINTER_FLAGS) --exclude vendor

.PHONY: clean
clean:
	@echo "Removing build artifacts"
	@rm -rf build
	@echo "Removing the image"
	-docker image rm $(CONTAINER_REGISTRY)/$(REPO_NAME):$(VERSION) > /dev/null 2>&1

.PHONY: compile
compile:
	@echo "Compiling the source for ${GOOS}"
	@env CGO_ENABLED=0 GOOS=${GOOS} GOARCH=amd64 go build -o build/${NAME} ./cmd/csi-driver/

.PHONY: test
test:
	@echo "Testing all packages"
	@go test -v ./...

# Hack to by pass go mod's inability to pull directories that are not directly referenced
# Note the use of rsync to drop perms, owner, and group on copy
TUNE_LINUX_CONFIG_PATH=$(shell go list -f {{.Dir}} github.com/hpe-storage/common-host-libs/tunelinux/config)
.PHONY: image
image:
	@echo "Building the docker image"

	cd build && \
	cp ../cmd/csi-driver/Dockerfile . && \
	cp ../cmd/csi-driver/rescan-scsi-bus.sh . && \
	cp -r ../cmd/csi-driver/conform/ conform/ && \
	cp -r ../cmd/csi-driver/diag/ diag/ && \
	rsync -r --no-perms --no-owner --no-group  $(TUNE_LINUX_CONFIG_PATH)/ tune/ && \
	docker build -t $(CONTAINER_REGISTRY)/$(REPO_NAME):$(VERSION) .

.PHONY: push
push:
	@echo "Publishing csi-driver:$(VERSION)"
	@docker push $(CONTAINER_REGISTRY)/$(REPO_NAME):$(VERSION)

