# Landing page

Static page (no build step): `index.html`, `style.css`, `main.js` (Three.js 0.169 from jsDelivr), the
Afacad Flux font subset to Latin as `fonts/AfacadFlux.woff2` (SIL Open Font License), and `mark.svg`.

Scroll drives five 3D scenes (drawer, plan path, streak, data, ship). The waitlist form posts to the relay
(`POST /waitlist`, see `relay/src/index.js`); `GET /waitlist/metrics` reports `signups`, which
`tools/prodline_metrics.py` adds to Prodline's own metrics feed.

```bash
python3 -m http.server 8790 --directory web          # local preview
npx wrangler pages deploy web --project-name prodline  # deploy (Cloudflare Pages)
```

Debug: `?still` turns off scroll smoothing and exposes `settle()` to run the springs to rest.
