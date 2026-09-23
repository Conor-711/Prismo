# Ticker Logos

The 2026-09-07 snapshot covers the fixture equity universe and the current XYZ
market catalog, plus already verified venue assets. `MARKET` is an account-level
sentinel with no open security, not a ticker needing a corporate logo.

- `ticker-logos.json`: source URL, installed filename, and SHA-256 of each asset.
- `Crypto_*.imageset`: original-color artwork from Hyperliquid's own
  `https://app.hyperliquid.xyz/coins/{coin}.svg` channel, not Simple Icons.
  `crypto-logos.json` records each source and SHA-256. Native-perp and stock
  namespaces remain separate to avoid symbol collisions. The 2026-09-22 sync
  covers 231 of 234 native contracts (including delisted historical markets);
  CANTO, MYRO and PEOPLE returned HTML instead of an image and use ticker text.
  Of 178 active native markets, 177 have a verified bundled logo.
  Official frontend `config-DWLPMyx3.js` confirms `/coins/`, the leading `k`
  multiplier removal, and white/colored backing overrides for transparent marks.
  Official SVGs are rendered without recoloring to lossless 256px transparent
  PNGs. This avoids expensive Xcode/runtime vector rendering of complex marks;
  the intermediate SVG viewport is bounded while preserving viewBox coordinates.
  The audit stores original-download and installed-PNG hashes. HYPE gets
  a dark green circular backing. Logos are bundled, so scrolling does not depend
  on image downloads.
- `../BSmart/Core/DesignSystem/TickerLogoRegistry.swift`: generated test inventory.
- Existing AVGO/HOOD/MSTR/NVDA/PLTR/TSLA assets retain their tuned rendering.
- Public venue assets: https://app.trade.xyz and its published `/markets/` paths.
- Equity images: https://financialmodelingprep.com/image-stock/{ticker}.png.
- DGXX, MRLN, UNITREE, SHEIN, YMTC: issuer websites, with explicit source overrides.
- LYTE/NCLD use the Roundhill issuer mark, not a made-up security-specific logo.
  Same-issuer ETFs can legitimately share a logo.

Run `python3 scripts/sync_ios_ticker_logos.py` to fill missing fixture assets using
the saved sources. To add newly verified venue mappings, pass `--official-scripts`
with the downloaded public app scripts and `--market-catalog` with a public
`metaAndAssetCtxs` response. Requires curl and Pillow. Downloads are bounded to
four workers; SVG/XML and raster decoding are checked before installation.

Run `TickerLogoTests` after XcodeGen to verify every registered image loads from
the compiled asset catalog. Downloads establish provenance, not a trademark or
redistribution license. Brand marks belong to their respective owners; review
distribution rights before a public release. Future listings and native crypto
markets beyond the explicitly bundled marks are not claimed to be covered.

Run `python3 scripts/sync_ios_crypto_logos.py` to refresh native-perp logos from
the official `info` / `meta` universe. `--meta PATH` accepts a saved response;
`--missing-only` retries unverified or missing files. Requires curl, Node.js and
the `sharp` module (resolvable normally or through `NODE_PATH`). The script honors
`HTTPS_PROXY`, uses four download workers, rejects HTML/external image references,
and sets original rendering explicitly. Failed refreshes retain previously
verified assets. Do not replace missing marks with guessed company/token logos.
