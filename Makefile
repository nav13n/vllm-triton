# Basic Project Settings
APP_PROJECT_NAME ?= vllm-triton
APP_BUILD_ENV ?= dev
SHELL := $(shell which bash)
CDIR := $(CURDIR)

# CI/CD Settings
LATEST_GIT_COMMIT ?= $(shell git log -1 --format=%h)
CI_BUILD_USERNAME ?= $(shell whoami)
CI_BUILD_UID ?= $(shell id -u)
CI_BUILD_GID ?= $(shell id -g)
GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
PIP_EXTRA_INDEX_URL := $(shell echo $$PIP_EXTRA_INDEX_URL)
PIP_EXTRA_INDEX_TRUSTED_HOST ?= $(shell echo $$PIP_EXTRA_INDEX_TRUSTED_HOST)

# Conda Environment Settings
ENV_FILE := "./environment.yaml"
CONDA_BIN := $(shell which mamba || which conda)

# Ensure conda or mamba is installed
ifeq ($(CONDA_BIN),)
$(error No mamba or conda installation found. Please install mamba or conda to continue.)
endif

CONDA_ROOT := $(shell $(CONDA_BIN) info --base)
APP_CONDA_ENV_NAME ?= venv-$(APP_PROJECT_NAME)
APP_CONDA_ENV_PREFIX := $(shell $(CONDA_BIN) env list | grep -m 1 $(APP_CONDA_ENV_NAME) | awk '{print $$NF}')
CONDA_ACTIVATE := source $(CONDA_ROOT)/etc/profile.d/conda.sh ; conda activate $(APP_CONDA_ENV_NAME) && PATH=$(APP_CONDA_ENV_PREFIX)/bin:${PATH}
ENV_BIN_DIR := $(APP_CONDA_ENV_PREFIX)/bin
ENV_LIB_DIR := $(APP_CONDA_ENV_PREFIX)/lib
ENV_PYTHON := $(ENV_BIN_DIR)/python
ENV_PIP := $(ENV_BIN_DIR)/pip

# Container Registry and Container Image variables
CR_REPO_URL ?= $(shell echo $$CR_REPO_URL)
CR_USERNAME ?= $(shell echo $$CR_USERNAME)
CR_PASSWORD ?= $(shell echo $$CR_PASSWORD)

CR_NAMESPACE_PREFIX ?= $(shell echo $$CR_NAMESPACE_PREFIX)
CR_NAMESPACE ?= $(shell echo $$CR_NAMESPACE)
CR_NAMESPACE_PATH := $(CR_NAMESPACE_PREFIX)/$(CR_NAMESPACE)

# Base image variables
BASE_CONTAINER_BASE_IMAGE := "nvcr.io/nvidia/tritonserver:24.01-py3"

# Application container variables
APP_CONTAINER_IMAGE_NAME:= $(APP_PROJECT_NAME)

ENABLE_APP_CONTAINER_IMAGE_TAG_ENV_SUFFIX ?= trusted
APP_CONTAINER_IMAGE_TAG_ENV_SUFFIX :=
ifeq ($(ENABLE_APP_CONTAINER_IMAGE_TAG_ENV_SUFFIX), true)
	APP_CONTAINER_IMAGE_TAG_ENV_SUFFIX := $(APP_BUILD_ENV)
endif

APP_CONTAINER_VERSION = $(shell cat VERSION | head -1 | awk '{$$1=$$1};1')

# Simplified Image Tags
define docker_image_tag
$(CR_REPO_URL)/$(CR_NAMESPACE_PATH)/$(1):$(2)$(3)$(4)
endef

# Base container image variables
APP_CONTAINER_IMAGE :=  $(call docker_image_tag,$(APP_PROJECT_NAME),$(APP_CONTAINER_VERSION),,$(APP_CONTAINER_IMAGE_TAG_ENV_SUFFIX))
APP_CONTAINER_IMAGE_LATEST :=  $(call docker_image_tag,$(APP_PROJECT_NAME),latest,,$(APP_CONTAINER_IMAGE_TAG_ENV_SUFFIX))


# Define phony targets
.PHONY: submodule-update \
	environment install build \
	start-cotainer stop-container \
	run test coverage \
	package-container publish-container \
	cr-login

# Makefile utils
print-%: ; @echo $(CDIR) $* is $($*)

check-env: print-APP_CONDA_ENV_NAME print-APP_CONDA_ENV_PREFIX

guard-env-%:
	@ if [ "${${*}}" = "" ]; then \
		echo "Environment variable $* not set"; \
		exit 1; \
	fi

# git utils
submodule-update:
	git submodule update --init --recursive --remote
	@echo "Git submodules updated"


update-origin:
	git checkout $(GIT_BRANCH)
	git push origin

update-alt:
	git pull origin $(GIT_BRANCH) || true
	git checkout dev
	git pull origin dev
	git push -u alt --all || git checkout $(GIT_BRANCH)
	git checkout $(GIT_BRANCH)

environment-chown:
ifneq ($(CONDA_ROOT),)
	sudo chown -R $(CI_BUILD_USERNAME):$(CI_BUILD_USERNAME) $(CONDA_ROOT)
endif

environment: guard-env-PIP_EXTRA_INDEX_URL submodule-update
	$(CONDA_BIN) remove -n $(APP_CONDA_ENV_NAME) --all -y --force-remove
	$(CONDA_BIN) env update -n $(APP_CONDA_ENV_NAME) -f $(ENV_FILE)
	$(CONDA_ACTIVATE) pip install \
		--upgrade --index-url=https://pypi.org/simple \
		--extra-index-url=$(PIP_EXTRA_INDEX_URL) \
		--trusted-host $(PIP_EXTRA_INDEX_TRUSTED_HOST) \
		-r requirements.txt 
	@echo " \u2713 Conda environment $(APP_CONDA_ENV_NAME) created and dependencies installed/updated..."

install: guard-env-PIP_EXTRA_INDEX_URL
	$(CONDA_BIN) env update -n $(APP_CONDA_ENV_NAME) -f $(ENV_FILE)
	$(CONDA_ACTIVATE) pip install \
		--upgrade --index-url=https://pypi.org/simple \
		--extra-index-url=$(PIP_EXTRA_INDEX_URL) \
		--trusted-host $(PIP_EXTRA_INDEX_TRUSTED_HOST) \
		-r requirements.txt
	@echo "\u2713 Dependencies installed/updated in $(APP_CONDA_ENV_NAME)..."

cr-login:
	docker login -u $(CR_USERNAME) -p $(CR_PASSWORD) $(CR_REPO_URL)
	@echo "\u2713 Container registry ($(CR_REPO_URL)) login successfull..."

start-container: 
	docker run --name $(APP_PROJECT_NAME) --rm --gpus all --net=host --rm -p 8001:8001 --shm-size=1G --ulimit memlock=-1 --ulimit stack=67108864 $(APP_CONTAINER_IMAGE) && sleep 5

stop-container:
	docker kill $(APP_PROJECT_NAME) || true

test: start-container
	$(CONDA_ACTIVATE) pytest tests/integration --cov-report term --cov-report html --cov . -vv --durations 0
	@echo "Tests Done"
	make -C . stop-container

profile: 
	@echo "Unit tests done..."

coverage:
	#rm -rf ./junit/test-results.xml ./coverage.xml ./htmlcov
	#$(CONDA_ACTIVATE) pytest tests/unit --doctest-modules --junitxml=junit/test-results.xml --cov=. --cov-report=xml --cov-report=html -v
	#@echo "Code coverage done..."

package-container:
	docker build \
		-t $(APP_CONTAINER_IMAGE) \
		-f ./deployment/docker/Dockerfile \
		--build-arg BASE_IMAGE=$(BASE_CONTAINER_BASE_IMAGE) \
		--build-arg http_proxy=$(http_proxy) \
		--build-arg https_proxy=$(https_proxy) \
		--build-arg no_proxy=$(no_proxy) \
		--build-arg PIP_EXTRA_INDEX_TRUSTED_HOST=$(PIP_EXTRA_INDEX_TRUSTED_HOST) \
		--build-arg PIP_EXTRA_INDEX_URL=$(PIP_EXTRA_INDEX_URL) \
		--build-arg GIT_COMMIT=$(shell git log -1 --format=%h) \
		.
	docker tag  $(APP_CONTAINER_IMAGE) $(APP_CONTAINER_IMAGE_LATEST)

publish-container: cr-login
	docker push $(APP_CONTAINER_IMAGE_LATEST)
	docker push $(APP_CONTAINER_IMAGE)
