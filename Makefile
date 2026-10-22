.PHONY: all build test run clean bootstrap

# Anon — top-level developer entry points.
#
#   make build    build the M0 packages and the runnable macOS app
#   make test     build + run the router behavior smoke tests
#   make run      build + launch the Anon app
#   make clean    remove build artifacts
#   make bootstrap  initialize submodules

all: build

bootstrap:
	git submodule update --init --recursive

build:
	./Tools/build-app.sh

test:
	./Tools/build-smoke.sh
	/tmp/anon-router-smoke

run: build
	open /tmp/Anon.app

clean:
	rm -rf /tmp/anon-build /tmp/Anon.app /tmp/anon-router-smoke
