.PHONY: build test generate open clean todo

build:
	swift build

test:
	swift test

generate:
	cd App && xcodegen generate

open: generate
	open App/Grade.xcodeproj

clean:
	swift package clean
	rm -rf App/Grade.xcodeproj

todo:
	python3 scripts/todo_server.py
