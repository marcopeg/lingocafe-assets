# Microsoft Fluent Emoji

- Repository: https://github.com/microsoft/fluentui-emoji
- Pinned commit: `62ecdc0d7ca5c6df32148c169556bc8d3782fca4`
- License: MIT; see `LICENSE`

The complete upstream distributable catalog and working selection are
downloaded into the Git-ignored `.vendor-cache/microsoft-fluent-emoji/`
directory. The SVG files listed in `selection.tsv` are copied into canonical
persona sources in `books`; `persona-push` then emits only immutable,
content-addressed copies into the assets image.

Run `./scripts/sync-fluent-emoji.sh` to recreate both the cache and the served
selection. Do not edit selected SVG files manually.
