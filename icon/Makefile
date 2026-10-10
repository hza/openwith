# source.png (opaque artwork) -> ../build/icon.png (rounded, transparent) -> app.icns
ICNS    := app.icns
PNG     := ../build/icon.png
ICONSET := ../build/app.iconset

all: $(ICNS) ## Regenerate app.icns from source.png (default)

$(PNG): source.png mask.swift
	mkdir -p $(dir $@)
	swift mask.swift $< $@

$(ICNS): $(PNG)
	rm -rf $(ICONSET) && mkdir $(ICONSET)
	for s in 16 32 128 256 512; do \
	  sips -z $$s $$s $< --out $(ICONSET)/icon_$${s}x$${s}.png >/dev/null; \
	  sips -z $$((s*2)) $$((s*2)) $< --out $(ICONSET)/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns $(ICONSET) -o $@
	rm -rf $(ICONSET)

clean: ## Remove the intermediate build/icon.png
	rm -rf $(PNG) $(ICONSET)

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: all clean help
