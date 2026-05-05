ADDON   := GuildConsumableLedger
VERSION  = $(shell grep '## Version' $(ADDON).toc | sed 's/.*: //')
OUTDIR  := dist
SRCDIRS := Core Data Locale Pricing Ledger Reimbursement Tracking UI

WOW_ADDONS := $(HOME)/.steam/steam/steamapps/compatdata/2832488321/pfx/drive_c/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns

.DEFAULT_GOAL := help
.PHONY: help release zip deploy clean

help: ## Show this help message
	@echo "$(ADDON) Makefile targets:"
	@echo
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Current version: $(VERSION)"

release: ## Bump patch version, commit, tag v<version>, and push (triggers GitHub release)
	@OLD=$$(grep '## Version' $(ADDON).toc | sed 's/.*: //'); \
	echo "Current version: $$OLD"; \
	if echo "$$OLD" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$'; then \
		PATCH=$$(echo $$OLD | cut -d. -f3); \
		NEW_PATCH=$$((PATCH + 1)); \
		NEW=$$(echo $$OLD | sed "s/\.[0-9]*$$/\.$$NEW_PATCH/"); \
		sed -i "s/## Version: .*/## Version: $$NEW/" $(ADDON).toc; \
		git add $(ADDON).toc; \
		git commit -m "chore: bump version $$OLD -> $$NEW"; \
		echo "Bumped version $$OLD -> $$NEW"; \
	else \
		echo "Non-semver version detected ($$OLD); skipping auto-bump. Edit $(ADDON).toc manually then re-run."; \
		exit 1; \
	fi
	@NEW_VERSION=$$(grep '## Version' $(ADDON).toc | sed 's/.*: //'); \
	echo "Tagging v$$NEW_VERSION and pushing to GitHub..."; \
	git tag -a "v$$NEW_VERSION" -m "Release v$$NEW_VERSION"; \
	git push origin HEAD; \
	git push origin "v$$NEW_VERSION"; \
	echo "GitHub Actions will build the release ZIP and attach it to the tag."

zip: ## Build the release ZIP locally into dist/
	@rm -rf $(OUTDIR)
	@VER=$(VERSION); \
	echo "Building $(ADDON)-$$VER.zip..."; \
	mkdir -p "$(OUTDIR)/$(ADDON)"; \
	cp $(ADDON).toc "$(OUTDIR)/$(ADDON)/"; \
	for dir in $(SRCDIRS); do \
		if [ -d "$$dir" ]; then cp -r "$$dir" "$(OUTDIR)/$(ADDON)/"; fi; \
	done; \
	cd $(OUTDIR) && zip -r "$(ADDON)-$$VER.zip" "$(ADDON)/"; \
	rm -rf "$(OUTDIR)/$(ADDON)"; \
	echo "Created $(OUTDIR)/$(ADDON)-$$VER.zip"

deploy: ## Copy addon files into the local WoW Interface/AddOns folder
	@echo "Deploying to WoW AddOns..."
	@DEST="$(WOW_ADDONS)/$(ADDON)"; \
	mkdir -p "$$DEST"; \
	cp $(ADDON).toc "$$DEST/"; \
	for dir in $(SRCDIRS); do \
		if [ -d "$$dir" ]; then \
			rm -rf "$$DEST/$$dir"; \
			cp -r "$$dir" "$$DEST/"; \
		fi; \
	done; \
	echo "Deployed to $$DEST"

clean: ## Remove the dist/ build directory
	@rm -rf $(OUTDIR)
