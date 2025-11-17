.PHONY: install compile watch deploy lits-watch package install-ext reinstall uninstall-ext clean help

help:
	@echo "Available targets:"
	@echo "  install      - Install npm dependencies"
	@echo "  compile      - Compile TypeScript files"
	@echo "  watch        - Watch and compile TypeScript files"
	@echo "  deploy       - Build for production using litscript"
	@echo "  lits-watch   - Watch mode with litscript development server"
	@echo "  package      - Create .vsix package file"
	@echo "  install-ext  - Install extension to VS Code"
	@echo "  reinstall    - Rebuild, package and reinstall extension"
	@echo "  uninstall-ext - Uninstall extension from VS Code"
	@echo "  clean        - Remove generated files"

install:
	npm install

compile:
	npm run compile

watch:
	npm run watch

deploy:
	npm run deploy

lits-watch:
	npm run lits-watch

package: deploy
	npx vsce package

install-ext: package
	code --install-extension $$(ls -t *.vsix | head -n 1)

reinstall: uninstall-ext package install-ext

uninstall-ext:
	code --uninstall-extension johtela.vscode-modaledit

clean:
	rm -rf out/ dist/ node_modules/ *.vsix
	rm -rf docs/*.html docs/*/*.html
