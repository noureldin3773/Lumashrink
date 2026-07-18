# LumaShrink launch checklist

## Required before accepting money

- [x] Add `scripts/build_public_release.sh` to fail fast on missing URLs, DNS, MX, Developer ID, or notarization credentials and automate signing, notarization, stapling, Gatekeeper assessment, verification, and checksum generation.
- [ ] Create the hosted checkout and set `LUMASHRINK_CHECKOUT_URL`.
- [ ] Confirm the checkout product is **LumaShrink Pro — $19 one-time** and includes the refund terms shown on the site.
- [ ] Replace `support@lumashrink.app` if that inbox is not live, then test it from the website and Mac app.
- [ ] Enroll in the Apple Developer Program, sign the app with a Developer ID certificate, notarize it, and staple the ticket.
- [ ] Upload the signed/notarized ZIP and set `LUMASHRINK_DOWNLOAD_URL` or configure checkout-provider fulfillment.
- [ ] Have a qualified lawyer review `/privacy` and `/terms` for the business entity and target countries.
- [ ] Publish over HTTPS and verify `/health`, `/buy`, `/download`, `/privacy`, `/terms`, and `/support`.

## Product verification

- [x] Run `scripts/verify_launch.sh` to test core pages, validation, upload, WebP compression, download naming, preview cleanup, and API cache policy.
- [x] Complete the browser-tree, form-label, heading, focus-style, reduced-motion, and computed contrast pass documented in `docs/accessibility/audits/audit-2026-07-15.md`.
- [x] Run `scripts/verify_release_media.sh` against the bundled helpers for JPEG, transparent PNG, WebP, HEIC, MP4, MOV, duplicate names, corrupt input, metadata, and an already-small file.
- [x] Test a target that cannot be reached and confirm the best-effort message is clear.
- [ ] Test Apple silicon on macOS 13 or newer; do not advertise Intel until a universal helper runtime is built and tested.
- [x] Make the FFmpeg requirement explicit on the sales/support pages and preflight it in the desktop app.
- [ ] Test keyboard-only navigation and Reduce Motion.
- [ ] Confirm files in web-trial sessions disappear within two hours and immediately after New.
- [x] Confirm source files are never overwritten by the default suffix settings.

## Release operations

- [x] Build `dist/LumaShrink-macOS.zip` and record its SHA-256 checksum in the launch handoff.
- [ ] Keep a rollback copy of the prior release.
- [ ] Add a real support response owner and a 24-hour launch-day monitoring schedule.
- [ ] Record purchase, download, activation, compression-success, and refund counts without collecting media.
