# Prodline: App Store submission

Everything for App Store Connect in one place. Part 1 is ready to paste. Part 2 (screenshots) and Part 3 (header and search assets) are drafts to sign off before the assets get built.

---

## Decide first

| | Proposal | Why |
|---|---|---|
| Price | Free, no in-app purchases | Matches "free during the beta"; the app has no StoreKit yet. Pricing can come in a later version. |
| App name | **Prodline: Side Project Tracker** (30/30) | The name field is the strongest search signal. Plain "Prodline" ranks for nothing yet. TestFlight then shows the long name too. |
| Release | Manual release after approval | So iPhone and Mac go live together and you can post the same day. |

---

## Part 1: Listing (paste-ready)

### App information (shared by iPhone and Mac)

**Name** (30 max)
```
Prodline: Side Project Tracker
```

**Subtitle** (30 max)
```
Deadlines, streaks, real stats
```

**Primary category:** Productivity
**Secondary category:** Developer Tools

**Content rights:** No, the app doesn't contain, show or access third-party content. (Integrations read the user's own accounts.)

**Copyright**
```
2026 Kian Jain
```

### Version information (iPhone version; repeat for the Mac version)

**Promotional text** (170 max, can change any time without review)
```
Give every side project a deadline, watch the real numbers come in, then decide: keep, pivot or kill. Now on iPhone and Mac.
```

**Keywords** (100/100, no spaces, no words from name or subtitle)
```
indie,hacker,startup,launch,ship,goal,habit,mrr,revenue,stripe,analytics,maker,planner,checklist,mvp
```

**Description**
```
Most side projects don't fail. They fade out. Prodline gives each one a short clock, so you ship it, see what happens and decide.

BUILD, LAUNCH, OBSERVE
Every project runs in two phases. A build phase of about two weeks, split into checkpoints with concrete goals. Then launch day, and an observe phase where you watch the numbers. At the end, Prodline checks them against the targets you set and suggests: keep, pivot or kill.

NUMBERS THAT COME IN ON THEIR OWN
Connect the tools you already use and the numbers arrive by themselves: revenue, visitors, downloads, signups, views. Goals like "first sale" or "100 visitors" tick themselves off the moment they happen.

• Revenue: Stripe, RevenueCat, App Store Connect, Lemon Squeezy, Paddle, Gumroad, Polar, Shopify
• Analytics: Plausible, Umami, Fathom, PostHog, Simple Analytics
• Hosting: Vercel, Netlify
• Newsletters: Kit, Buttondown, beehiiv
• Launches and social: YouTube, TikTok, Instagram, Bluesky, Product Hunt, Hacker News, npm
• GitHub: link a repo and its issues become goals. Commits count toward your momentum.

A STREAK WORTH KEEPING
Tick off goals, earn XP, keep your streak alive. A weekly wrap shows what you shipped. Widgets and a deadline Live Activity keep the next checkpoint in sight.

ON YOUR MAC TOO
A native Mac app with a dashboard, a calendar of every deadline and a menu bar item. Your projects stay in step through iCloud.

PRIVATE BY DESIGN
No account. Your projects live on your devices and in your own iCloud. API keys stay in your Keychain and the app talks to each service directly. No ads, no tracking.
```

**Support URL:** `https://prodline.build/faq.html`
**Marketing URL:** `https://prodline.build`
**Privacy policy URL:** `https://prodline.build/privacy.html`

### Mac version

Universal purchase, so the Mac app is a second platform on the same app record (App Store Connect → the app → "+ Add platform" → macOS if it isn't there yet). Name, subtitle and privacy are shared. Description, keywords, promotional text and screenshots are per platform: paste the same texts, and add the Mac screenshots from Part 2.

### Age rating

Answer **None** or **No** to every question (no violence, no mature themes, no gambling, no user-generated content shared with others, no unrestricted web access, no messaging, no advertising). Result: **4+**.

### App Privacy ("nutrition label")

Matches `PrivacyInfo.xcprivacy`. **Tracking: No.**

| Data type | Collected | Linked to the user | Used for tracking | Purpose |
|---|---|---|---|---|
| Identifiers → Device ID | Yes (push token, only when instant GitHub updates are on) | No | No | App Functionality |
| User Content → Other User Content | Yes (the GitHub repo name, sent to the relay for instant updates) | No | No | App Functionality |

Everything else: **not collected**. Projects sync through the user's private iCloud database (that's not data we collect). Feedback goes out as an email the user sends from Mail.

### Export compliance

Already answered in the build (`ITSAppUsesNonExemptEncryption = NO`). Nothing to fill in.

### App Review information

**Sign-in required:** No

**Notes**
```
Prodline has no account and no backend for user data: projects are stored on the device and synced through the user's private iCloud database.

To try it:
1. Finish the short onboarding, then tap "New project" and create a project.
2. Open the project. Under "Connected", tap + to see the integrations.
3. Most integrations need the user's own API key for that service. Three work without one, so you can see live data: Hacker News, npm and Bluesky. GitHub works without a token for public repositories: link the repository "expbsn/prodline". Its issues become goals, and its prodline.json plan file adds goals that tick off as the developer pushes.
4. Take a screenshot anywhere in the app to see the feedback prompt (it opens Mail).

The Mac app (same app record, universal purchase) shows the same projects through iCloud and adds a menu bar item.

Notifications are used for checkpoint reminders and when a goal completes itself. Push notifications only carry "something changed" signals for GitHub repos the user linked.
```

**Contact:** your name, phone and email (filled in App Store Connect).

### What's New

Not needed for 1.0.

---

## Part 2: Screenshot draft

### Sizes

| Platform | Size | Status |
|---|---|---|
| iPhone 6.1" (Dynamic Island, medium) | 1206 × 2622 | **Required** |
| iPhone 6.9" (Dynamic Island, large) | 1320 × 2868 | Optional, built from the same layouts |
| iPhone Duo | 1398 × 2034 / 2007 × 2853 | Optional now, required from April 2027. Skip for 1.0. |
| Mac | 2880 × 1800 | **Required** for the Mac app |

### Style

- The app's own look: light background (`Theme.background`), Afacad Flux for the headline, the chunky card shadows.
- Each frame: a short headline (2–5 words) and one subline, then the real screen below it, in a rounded phone outline that bleeds off the bottom edge.
- Light mode for all frames except one dark frame (the widgets) for contrast in the row.
- Real app screens from the simulator with the store demo data below, no mock-ups.

### Store demo data (replaces the stock photos)

New covers are drawn logos: `design/demo-logos/` (habit-hero, pixel-quest, side-shop, tiny-invoice, moonlog). A DEBUG-only launch argument (`-PRODLINE_STORE YES`) seeds this set on iPhone and Mac, offline, with history for the charts.

| Project | What it is | Phase | Connected | Numbers shown |
|---|---|---|---|---|
| **Tiny Invoice** | Invoices for freelancers | Observing, day 12 of 28 | Stripe, Plausible, GitHub | $1,240 revenue · 3,180 visitors · 46 signups |
| **Pixel Quest** | Daily pixel art puzzles | Observing, day 26 of 28, targets met → **Keep** suggested | App Store Connect, YouTube, TikTok | 2,860 downloads · 41.2K views · 312 followers |
| **Habit Hero** | Habit tracker with plants | Building, day 9 of 14 | App Store Connect, RevenueCat, GitHub | 86 downloads · 14 trials |
| **Side Shop** | One-page print shop | Building, day 3 of 14 | Shopify, Plausible | 180 visitors |
| **Moonlog** | Journaling newsletter | Finished, **Kept** | Kit, Bluesky | 1,920 subscribers |

Profile: level 7, 12-day streak, 91% on time. Goals come from all sources (GitHub issues, prodline.json, metric targets, typed), so the source icons show.

### iPhone frames

| # | Headline | Subline | Screen |
|---|---|---|---|
| 1 | **Finish what you start.** | Every side project on a short clock. | Dash: the project carousel on Tiny Invoice, streak flame lit, today's checkpoint below |
| 2 | **Numbers, on their own.** | Revenue, visitors and downloads arrive by themselves. | Tiny Invoice project page: revenue chart, three tiles, Stripe · Plausible · GitHub connected |
| 3 | **Goals that tick themselves off.** | "First sale" happens, the goal is done. | Habit Hero checkpoints: goals from GitHub issues and a metric target ticked, one "Up next" |
| 4 | **25+ services, connected.** | Keys stay in your Keychain. | The integration picker grid |
| 5 | **Keep, pivot or kill.** | Decide on real numbers, not on feelings. | Pixel Quest decision sheet, targets met, Keep suggested |
| 6 | **Your streak, everywhere.** | Widgets and a deadline Live Activity. | Dark: Home Screen widgets (small streak, medium traction) and the Lock Screen Live Activity, composed from the widget views on a wallpaper |
| 7 | **Your week, wrapped.** | What you shipped, every Sunday. | The weekly wrap's main card (optional, if the row feels short) |

### Mac frames

Full window (1440 × 900 points, so 2880 × 1800 at 2×) on a soft backdrop, headline above the window.

| # | Headline | Screen |
|---|---|---|
| 1 | **Your week at a glance.** | Dash: stats strip, Up next, Coming up, Activity |
| 2 | **Live numbers for every project.** | Tiny Invoice project page with the chart and connected services |
| 3 | **Every deadline in one place.** | Plan: agenda and month calendar |
| 4 | **Always one click away.** | The menu bar panel open over the desktop |
| 5 | **Plan a build in a minute.** | The create-project flow on its schedule step |

---

## Part 3: Header and search results assets (new since October)

Optional, shown only on iOS 27 / iPadOS 27 and later. They're submitted from the version page's "Header and Search Results" tab (or the Asset Library) and reviewed separately from the build, so they can go in after the app is approved. Rules: no prices, URLs, copyright signs, other platforms' logos or awards, content suitable for 4+, no transparency.

### Product page header: 21:9, 3840 × 1646, PNG

Sits at the very top of the product page. The app icon, name and Get button appear below it, not on it. One idea, mood over features.

**Concept: "the shelf of finished things."** A soft light gradient in the app's background tone. The five demo project cards (logos, phase line, one number each) stand in a gentle arc across the middle, the center card (Tiny Invoice, "$1,240") slightly larger and lifted, the outer ones fading into the background. One line above the cards, centered:

> Finish what you start.

Everything important stays inside the middle 3:2 area, so a crop never cuts a card in half.

### Search results asset: 3:2, 3840 × 2560, PNG

Replaces the screenshot row in search results (if left out, the first screenshots show as now). It should be a real screen plus one line that adds to it.

**Concept:** left third: the headline in Afacad Flux, large:

> Your side projects, on a deadline.

Right two thirds: two phone screens side by side, slightly overlapping. Tiny Invoice's project page (chart) in front, Dash behind it. Same background as the header so both read as one campaign.

**Video (later):** both slots also take 5–30 s loops. A 10-second loop of a goal ticking itself off and the streak flame lighting would be the strongest version, using the app's existing animations. Not needed for 1.0.

---

## Order of work after sign-off

1. Store demo data and logos into the app (DEBUG only).
2. iPhone frames at 1206 × 2622 and 1320 × 2868, Mac frames at 2880 × 1800, into `marketing/app-store/`.
3. Header and search assets into `marketing/app-store/`.
4. You: paste Part 1, upload the screenshots, select the build, submit both platforms. After approval: upload the header and search assets.
