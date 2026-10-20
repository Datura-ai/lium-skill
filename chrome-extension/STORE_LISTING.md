# Chrome Web Store listing — Lium GPU Prices

**Name:** Lium GPU Prices

**Category:** Developer Tools · **Language:** English

**Short description (max 132 characters):**
Live cloud GPU prices on Lium: H100, H200, B200, RTX 4090 and more, cheapest per GPU-hour first. One click to rent.

**Long description:**
See what a cloud GPU costs right now, without opening a tab.

Lium GPU Prices shows every GPU model available on Lium (lium.io) at this moment, sorted by the lowest price per GPU-hour, with VRAM and the number of GPUs free to rent. Click a model to open its page on lium.io and rent it by the hour.

Lium is a GPU cloud for developers and AI agents: rent NVIDIA H100, H200, B200, B300, A100, RTX 4090, RTX 5090 and more by the hour, from the browser, the `lium` CLI, the Python SDK, or straight from Claude Code and Codex through the Lium agent skill.

- Live prices from Lium's public price feed (lium.io/pricing.json)
- Cheapest available GPU first, with VRAM and free GPU count
- No account, no sign-in, no tracking

**Homepage / support URL:** https://lium.io

**Single purpose:** Show current GPU rental prices on Lium.

**Permission justification:** `https://lium.io/pricing.json` — the only host the extension contacts, to read the public price list. No other permissions.

**Remote code:** No. All code ships in the package.

**Privacy (data usage disclosure):** This extension collects no user data. It makes one request, to https://lium.io/pricing.json, when the popup opens; it stores nothing, sets no cookies and has no analytics. Links to lium.io carry a `utm_source=chrome-extension` tag so Lium can count visits from the extension.

**Screenshots:** one 1280x800 capture of the open popup.

**Package:** zip the contents of `chrome-extension/` (manifest.json at the zip root), leaving out `STORE_LISTING.md` and `prices.test.mjs`.
