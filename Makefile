.PHONY: build test watch watch-start watch-stop watch-status clean

build:
	./scripts/build-vgadget.sh

test:
	lua tests/test_core.lua
	luac -p Gridfinity_Baseplate.lua tests/test_core.lua

watch:
	./scripts/watch-vgadget.sh run

watch-start:
	./scripts/watch-vgadget.sh start

watch-stop:
	./scripts/watch-vgadget.sh stop

watch-status:
	./scripts/watch-vgadget.sh status

clean:
	find dist -maxdepth 1 -type f -name '*.vgadget' -delete 2>/dev/null || true
