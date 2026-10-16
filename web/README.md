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
python3 -m http.server 8790 --directory web          # local preview
npx wrangler pages deploy web --project-name prodline  # deploy (Cloudflare Pages)
```

## App Store Connect

- Support URL: `<site>/faq.html` (FAQ + contact). Privacy Policy URL: `<site>/privacy.html`. Marketing URL: `<site>/`.
- The contact address `support@prodline.app` in `faq.html`, `privacy.html` and `index.html` is a placeholder:
  replace it with a real, monitored address before submitting.
- The "Coming soon on the App Store" button is our own. Once the app is live, swap in Apple's official
  "Download on the App Store" badge (unmodified, from Apple's marketing tools) linking to the product page.
