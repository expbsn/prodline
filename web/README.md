# Landing page

Static page (no build step, no dependencies): `index.html`, `style.css`, `main.js`, the Afacad Flux font
subset to Latin as `fonts/AfacadFlux.woff2` (SIL Open Font License), and `mark.svg` / `mark-light.svg`.

Greys with red, green, blue and yellow accents; the phone screens are HTML/CSS mockups of the app. Sections
blur in on scroll and the hand-drawn lines draw themselves (`[data-reveal]`, `.draw`). Bump the `?v=` on the
CSS/JS links in `index.html` after changing them. The waitlist form posts to the relay
(`POST /waitlist`, see `relay/src/index.js`); `GET /waitlist/metrics` reports `signups`, which
`tools/prodline_metrics.py` adds to Prodline's own metrics feed.

```bash
python3 -m http.server 8790 --directory web          # local preview
npx wrangler pages deploy web --project-name prodline  # deploy (Cloudflare Pages)
```
