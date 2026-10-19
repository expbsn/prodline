# Landing page

Static page (no build step, no dependencies): `index.html`, `style.css`, `main.js`, the Afacad Flux font
subset to Latin as `fonts/AfacadFlux.woff2` (SIL Open Font License), and `mark.svg` / `mark-light.svg`.

Dark and greyscale; the color comes from the header photo and the real app screens in `shots/` (simulator, `-PRODLINE_DEMO YES`,
status bar set to 9:41 with `xcrun simctl status_bar`). Sections
blur in on scroll and the hand-drawn lines draw themselves (`[data-reveal]`, `.draw`). Bump the `?v=` on the
CSS/JS links in `index.html` after changing them. The waitlist form posts to the relay
(`POST /waitlist`, see `relay/src/index.js`); `GET /waitlist/metrics` reports `signups`, which
`tools/prodline_metrics.py` adds to Prodline's own metrics feed.

```bash
python3 -m http.server 8790 --directory web   # local preview
./web/deploy.sh                               # deploy (Cloudflare static assets, token from relay/.env)
```

## App Store Connect

Live at https://prodline-site.prodline-relay.workers.dev until a domain is connected.

- Support URL: https://prodline-site.prodline-relay.workers.dev/faq (FAQ + contact)
- Privacy Policy URL: https://prodline-site.prodline-relay.workers.dev/privacy
- Terms of service: https://prodline-site.prodline-relay.workers.dev/terms (also the Terms of Service URL for the TikTok and Meta developer apps)
- License Agreement (App Store Connect → App Information): leave it on Apple's standard EULA; the terms page builds on it. A link to it is only required once the app sells auto-renewable subscriptions.
- Marketing URL: https://prodline-site.prodline-relay.workers.dev/
- Support contact (FAQ, privacy page, footer): `exp.bsn@gmail.com`.
- The "Coming soon on the App Store" button is our own. Once the app is live, swap in Apple's official
  "Download on the App Store" badge (unmodified, from Apple's marketing tools) linking to the product page.

## Where signups come from

Link to the site with a tag, e.g. `prodline.build/?ref=sideproject`. The page keeps the tag for the visit and
sends it with a waitlist signup; the relay counts signups per tag, and `tools/prodline_metrics.py` reports
them in Prodline's own feed as `signups_from_<tag>` next to `signups` (no tag counts as `direct`).
