.PHONY: all install build run start test package clean

all: build

install:
	./build_and_package.sh

build:
	xcodegen generate
	xcodebuild -project Grasslook.xcodeproj -scheme Grasslook -configuration Release -derivedDataPath .derivedData build

run:
	open .derivedData/Build/Products/Debug/Grasslook.app || open .derivedData/Build/Products/Release/Grasslook.app || open /Applications/Grasslook.app

start: run

test:
	xcodebuild -project Grasslook.xcodeproj -scheme Grasslook -derivedDataPath .derivedData test

package:
	./build_and_package.sh

clean:
	rm -rf .derivedData dist npm/app
