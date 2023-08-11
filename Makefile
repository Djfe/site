GLUON_GIT_URL := https://github.com/freifunk-gluon/gluon.git
GLUON_GIT_REF := v2022.1.4
GLUON_TARGETS ?= $(shell cat targets | tr '\n' ' ')
GLUON_BUILD_DIR := gluon-build

export GLUON_SITEDIR := ..
PATCH_DIR := patches
SECRET_KEY_FILE ?= $(HOME)/.gluon-secret-key
OPKG_KEY_BUILD_DIR ?= $(HOME)/.key-build


## Create version scheme
EXP_FALLBACK = $(shell date '+%Y%m%d')
BUILD_NUMBER ?= $(EXP_FALLBACK)
GIT_TAG := $(shell git describe --tags 2>/dev/null)
ifeq (,$(GIT_TAG))
ifndef GLUON_RELEASE
$(error Set GLUON_RELEASE or create a git tag)
endif
endif
ifneq (,$(shell git describe --exact-match --tags 2>/dev/null))
	GLUON_RELEASE ?= $(GIT_TAG)
else
	GLUON_RELEASE ?= $(GIT_TAG)~exp$(BUILD_NUMBER)
endif
export GLUON_RELEASE


## Setup MAKE
JOBS ?= $(shell cat /proc/cpuinfo | grep -c ^processor)
MAKEFLAGS += -j$(JOBS)
MAKEFLAGS += --no-print-directory
MAKEFLAGS += --output-sync

GLUON_MAKE = $(MAKE) -C $(GLUON_BUILD_DIR)


## Build strings for INFO
define newline


endef
ifneq (,$(filter GLUON_TARGETS%,$(MAKEOVERRIDES)))
	TARGETS_INFO := $(newline)\# for target(s) '$(GLUON_TARGETS)'
endif
ifneq (,$(filter GLUON_DEVICES%,$(MAKEOVERRIDES)))
	DEVICE_INFO := $(newline)\# for device(s) '$(GLUON_DEVICES)'
endif


## Info section
define INFO :=

#########################
# FFAC Firmware build
# building release '$(GLUON_RELEASE)'$(TARGETS_INFO)$(DEVICE_INFO)
#########################
# MAKEFLAGS:
# $(MAKEFLAGS)
#########################
# git url: $(GLUON_GIT_URL)
# git ref: $(GLUON_GIT_REF)
#########################
# Found $(shell ls -1 $(PATCH_DIR) 2>/dev/null | wc -l) patches
#########################

endef
# show info section for all make calls except the filtered ones
ifneq (,$(filter-out gluon-clean output-clean clean,$(MAKECMDGOALS)))
$(info $(INFO))
endif


$(GLUON_BUILD_DIR):
	mkdir -p $(GLUON_BUILD_DIR)

# Note: "|" means "order only", e.g. "do not care about folder timestamps"
# https://www.gnu.org/savannah-checkouts/gnu/make/manual/html_node/Prerequisite-Types.html
$(GLUON_BUILD_DIR)/.git: | $(GLUON_BUILD_DIR)
	git init $(GLUON_BUILD_DIR)
	cd $(GLUON_BUILD_DIR) && git remote add origin $(GLUON_GIT_URL)

gluon-update: | $(GLUON_BUILD_DIR)/.git
	cd $(GLUON_BUILD_DIR) && git fetch --tags origin $(GLUON_GIT_REF)
	cd $(GLUON_BUILD_DIR) && git reset --hard FETCH_HEAD
	cd $(GLUON_BUILD_DIR) && git clean -fd


## Build rules
all: manifest

sign: manifest
	$(GLUON_BUILD_DIR)/contrib/sign.sh $(SECRET_KEY_FILE) output/images/sysupgrade/$(GLUON_AUTOUPDATER_BRANCH).manifest

# Note: $(GLUON_MAKE) is a recursive variable so it doesn't count as a $(MAKE).
# "+" tells MAKE that there is another $(MAKE) in the following shell script.
# This allows communication of MAKEFLAGS like -j to submake.
# https://stackoverflow.com/a/60706372/2721478
manifest: build
	+for branch in experimental beta stable; do \
		$(GLUON_MAKE) manifest GLUON_AUTOUPDATER_BRANCH=$$branch;\
	done

build: gluon-prepare output-clean
	cp OPKG_KEY_BUILD_DIR/* $(GLUON_BUILD_DIR)/openwrt || true
	+for target in $(GLUON_TARGETS); do \
		echo ''Building target $$target''; \
		$(GLUON_MAKE) download all GLUON_TARGET=$$target CONFIG_JSON_ADD_IMAGE_INFO=1; \
	done
	mkdir -p $(GLUON_BUILD_DIR)/output/opkg-packages
	cp -r $(GLUON_BUILD_DIR)/openwrt/bin/packages $(GLUON_BUILD_DIR)/output/opkg-packages/gluon-ffac-$(GLUON_RELEASE)/

gluon-prepare: gluon-update
	make gluon-patch
	+$(GLUON_MAKE) update

gluon-patch:
	echo 'Applying Patches ...'
	(cd $(GLUON_BUILD_DIR))
			if [ `git branch --list patched` ]; then \
				(git branch -D patched) \
			fi
	(cd $(GLUON_BUILD_DIR); git checkout -B patching)
	if [ -d 'gluon-build/site/patches' -a 'gluon-build/site/patches/*.patch' ]; then \
		(cd $(GLUON_BUILD_DIR); git apply --ignore-space-change --ignore-whitespace --whitespace=nowarn --verbose site/patches/*.patch) || ( \
			cd $(GLUON_BUILD_DIR); \
			git clean -fd; \
			git checkout -B patched; \
			git branch -D patching; \
			exit 1 \
		) \
	fi
	(cd $(GLUON_BUILD_DIR); git branch -M patched)

gluon-clean:
	rm -rf $(GLUON_BUILD_DIR)

output-clean:
	mkdir -p output/
	rm -rf output/*

clean: gluon-clean output-clean
