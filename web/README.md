# Landing page

Static page (no build step, no dependencies): `index.html`, `style.css`, `main.js`, the Afacad Flux font
subset to Latin as `fonts/AfacadFlux.woff2` (SIL Open Font License), and `mark.svg` / `mark-light.svg`.

Dark and greyscale; the color comes from the header photo and the real app screens in `shots/` (simulator, `-PRODLINE_DEMO YES`,
status bar set to 9:41 with `xcrun simctl status_bar`). Sections
blur in on scroll and the hand-drawn lines draw themselves (`[data-reveal]`, `.draw`). Bump the `?v=` on the
CSS/JS links in `index.html` after changing them. "Join the beta" buttons (`[data-beta]`) go straight to the
public TestFlight link (https://testflight.apple.com/join/QjY366XF); main.js counts each click with a beacon to
`POST /waitlist/click`. The launch email form under it posts to `POST /waitlist`. `GET /waitlist/metrics`
reports `signups` and `testflight_clicks` (plus `_from_<ref>` per source), which `tools/prodline_metrics.py`
adds to Prodline's own metrics feed.

```bash
python3 -m http.server 8790 --directory web   # local preview
./web/deploy.sh                               # deploy (Cloudflare static assets, token from relay/.env)
```

## App Store Connect

Live at https://prodline.build (domain registered with Cloudflare). www.prodline.build and the old prodline-site.prodline-relay.workers.dev address redirect there (`worker.js`).

- Support URL: https://prodline.build/faq (FAQ + contact)
- Privacy Policy URL: https://prodline.build/privacy
- Terms of service: https://prodline.build/terms (also the Terms of Service URL for the TikTok and Meta developer apps)
- License Agreement (App Store Connect → App Information): leave it on Apple's standard EULA; the terms page builds on it. A link to it is only required once the app sells auto-renewable subscriptions.
- Marketing URL: https://prodline.build/
- Support contact (FAQ, privacy page, footer, in-app feedback): `info@prodline.build`. Press and business: `inquiries@prodline.build`. Both forward to exp.bsn@gmail.com (Cloudflare Email Routing).
- The "Coming soon on the App Store" button is our own: Apple's badge may only be used once the app can be
  downloaded (or the separate "Pre-order" badge during a pre-order). At launch, replace both `.btn.store`
  links in index.html with `img/app-store-badge.svg` (Apple's black US/UK badge, unmodified) linking to the
  product page: at least 40 px tall, clear space of a quarter of its height, not the dominant element.
  Apple asks for one badge per layout, so keep the one in the header and drop the one in the join card.

## Where signups come from

Link to the site with a tag, e.g. `prodline.build/?ref=sideproject`. The page keeps the tag for the visit and
sends it with a waitlist signup; the relay counts signups per tag, and `tools/prodline_metrics.py` reports
them in Prodline's own feed as `signups_from_<tag>` next to `signups` (no tag counts as `direct`).
