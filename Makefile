.PHONY: build package package-linux zip run icon clean

build:
	./build.sh

package: zip

package-linux:
	./scripts/package_linux.sh

zip:
	./scripts/package_zip.sh

run:
	swift run

icon:
	./scripts/generate_icon_assets.sh

clean:
	rm -rf .build dist linux/build
