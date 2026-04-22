# meetup

- **Package:** `com.meetup`
- **Target version:** `2026.04.10.2881`
- **Patches module:** `:patches:meetup`

## APKs

The `apks/` directory is git-ignored — APKs are the vendor's IP and cannot be redistributed here. Obtain them yourself from a reputable mirror and place them in `apks/`.

Expected files and checksums (SHA-256):

| File | SHA-256 |
|------|---------|
| `base.apk` | `f394e3c07d4193378bb6d46bf4d1009cfe1e064d33e781eea73025d5e82817d2` |
| `com.meetup.apks` | `c63d7fd268e43d5aadbcd4491a8565624c4ab3624abe4d08ee6fec73f3fb2511` |
| `split_config.arm64_v8a.apk` | `02c74c7ff0042c7001093d392ee096a60ccb2e9895fa3f27a0b178c786fa87ed` |
| `split_config.en.apk` | `37da737dca4ab3d189aa66ce970e4fe757f54bc7a61ee45037815d1ea49c232b` |
| `split_config.xxhdpi.apk` | `c9fedafb6e7f694f35cb89a1a6886b58fab2cc6931c2048ea376a00ca1646cba` |


## Applying patches

From the repo root:

```bash
./patch-apks.sh --app meetup
```

## Writing patches

Place Kotlin patch files under `patches/meetup/src/main/kotlin/app/revanced/patches/meetup/`. Each patch should:

- Use the `bytecodePatch { ... }` DSL
- Declare `compatibleWith("com.meetup"("2026.04.10.2881"))`
- Anchor fingerprints on fully-qualified class types rather than opcode patterns
