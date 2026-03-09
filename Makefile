.PHONY: build package zip run icon clean

build:
	./build.sh

package: zip

zip:
	./scripts/package_zip.sh

run:
	swift run

icon:
	./scripts/generate_icon_assets.sh

clean:
	rm -rf .build dist
