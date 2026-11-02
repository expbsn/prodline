# SEO audit: prodline.build

November 2, 2026, made with the claude-seo plugin (`/seo audit`). Goal: people building side projects find the landing page.

**Business type:** consumer app (iPhone, with a Mac app), free, in beta on TestFlight. Six pages: home, docs, faq, privacy, terms, impressum.

## Score

| Category | Weight | Before | After (estimate) |
|---|---|---|---|
| Technical SEO | 22% | 60 | 85 |
| Content quality | 23% | 45 | 55 |
| On-page SEO | 20% | 50 | 80 |
| Schema / structured data | 10% | 0 | 85 |
| Performance | 10% | 70 | 80 |
| AI search readiness | 10% | 40 | 75 |
| Images | 5% | 80 | 85 |
| **SEO health** | | **49** | **~74** |

Content stays the weak spot: the home page has about 300 words and no page answers what people search for beyond the brand.

## What was wrong, and what changed

| Severity | Finding | Fix |
|---|---|---|
| High | No `sitemap.xml` (404), and robots.txt doesn't point to one | `web/sitemap.xml` (6 URLs), `web/robots.txt` with the `Sitemap:` line. Cloudflare still prepends its content-signal comments. |
| High | Title, H1 and headings never say what the product is in search words ("side project", "indie hacker", "tracker") | Title "Prodline · Side project tracker for indie hackers", H1 "Watch your side projects take off.", new description, three ledes now name side project tracker, indie hackers / solo founders, Stripe revenue, Plausible visitors, App Store Connect downloads |
| High | No canonical URLs on any page | `<link rel="canonical">` on all six pages, clean URLs |
| Medium | Every internal link (`docs.html`, `faq.html` …) answers with a temporary 307 redirect to `/docs` | Links point at `/docs`, `/faq` … directly |
| Medium | No structured data | JSON-LD on the home page: WebSite, Organization, MobileApplication (free offer, screenshots). No ratings until there are real ones. |
| Medium | Only two Open Graph tags, no image: shared links show no preview | Full OG and Twitter card set on every page, `img/og.jpg` (1200 × 630, the header photo with the headline) |
| Medium | Header photo (the page's largest paint) is 908 KB for every screen | `srcset`: 263 KB at 1600 px, 643 KB at 2400 px, the original only for large retina screens |
| Low | No `llms.txt` | `web/llms.txt` with what Prodline is and the four useful pages (optional; Google ignores it, some AI assistants read it) |
| Low | Sub pages still linked `style.css?v=48` | Bumped to `v=49` |
| Info | No security headers (HSTS, CSP). No ranking effect; worth adding in `worker.js` later | Not changed |

Checked and fine: HTTPS, `www` and workers.dev redirect permanently (301) to prodline.build, `lang="en"`, one H1 per page, all content images have alt text, no console errors, not a single-page app (the HTML is fully readable without JavaScript).

## Next steps (not done)

1. **Google Search Console and Bing Webmaster Tools.** Verify prodline.build (DNS TXT record in Cloudflare), submit `https://prodline.build/sitemap.xml`. Leading indicator: pages indexed and first impressions for "side project tracker" within 2–4 weeks.
2. **Pages that match searches.** The home page can rank for the brand and maybe "side project tracker"; the rest of the demand is questions. One page each, written from the app's real behavior:
   - "How to finish side projects" (short builds, checkpoints, the streak)
   - "Track MRR and revenue for side projects" (Stripe, RevenueCat, Lemon Squeezy, Gumroad …)
   - "Keep, pivot or kill a side project" (the decision at the end)
   - Each integration as its own docs anchor is already there; a short page per big one ("Stripe revenue on your iPhone Home Screen") would catch long-tail searches.
3. **Links from where indie hackers are.** Product Hunt, Indie Hackers, Show HN, r/SideProject, BetaList and app directories (see `marketing/launch-posts.md`). A new domain with no links ranks for almost nothing, whatever the on-page work.
4. **App Store link.** When the app is live, link the App Store page from the hero and add it to the JSON-LD (`downloadUrl`), and only then add ratings.

How we'd know this failed: no impressions for non-brand queries in Search Console after six weeks. Then the page content (step 2) and links (step 3) are the problem, not the tags.
