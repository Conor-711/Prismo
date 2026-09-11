# Ticker Logos

The 2026-09-07 snapshot covers the fixture equity universe and the current XYZ
market catalog, plus already verified venue assets. `MARKET` is an account-level
sentinel with no open security, not a ticker needing a corporate logo.

- `ticker-logos.json`: source URL, installed filename, and SHA-256 of each asset.
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
markets are not claimed to be covered by this equity/XYZ snapshot.
