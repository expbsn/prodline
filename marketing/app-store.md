# Prodline: App Store submission

Everything for App Store Connect in one place. Part 1 is ready to paste; Parts 2 and 3 are built and live in `marketing/app-store/`.

---

## Decided

Free, no in-app purchases. Name **Prodline: Side Project Tracker**. Manual release after approval, so iPhone and Mac go live together.

---

## Part 1: Listing (paste-ready)

### App information (shared by iPhone and Mac)

**Name** (30 max)
```
Prodline: Side Project Tracker
```

**Subtitle** (30/30)
```
Ship it: deadlines, goals, MRR
```
The name and subtitle carry the most search weight, so together they cover "side project", "tracker", "ship", "deadline", "goal" and "MRR". The keyword field below doesn't repeat any of them; Apple combines words across all three fields ("indie" + "hacker", "habit" + "tracker").

**Primary category:** Productivity
**Secondary category:** Developer Tools

**Content rights:** No, the app doesn't contain, show or access third-party content. (Integrations read the user's own accounts.)

**Copyright**
```
2026 Kian Jain
```

### Version information (iPhone version; repeat for the Mac version)

**Promotional text** (154/170, can change any time without review)
```
Now on iPhone and Mac. Give every side project a short deadline, watch revenue and visitors come in from Stripe and co., then decide: keep, pivot or kill.
```

**Keywords** (100/100, no spaces, nothing from the name or subtitle)
```
indie,hacker,startup,founder,launch,saas,maker,mvp,revenue,stripe,analytics,planner,habit,streak,dev
```

**Description** (the first three lines show before "more", so they carry the pitch)
```
Most side projects don't fail. They fade out. Prodline puts each one on a short clock: build it in two weeks, launch it, watch the real numbers, then decide to keep, pivot or kill it.

Made for indie hackers, makers and solo founders with more ideas than evenings.

BUILD IN CHECKPOINTS
Every project gets a build phase of about two weeks, split into checkpoints with concrete goals and deadlines. Link a GitHub repo and its issues turn into goals; your commits count toward your momentum.

LIVE NUMBERS, NO SPREADSHEET
Connect the tools you already use and revenue, MRR, visitors, downloads, signups and views come in by themselves. Goals like "first sale" or "100 visitors" tick themselves off the moment they happen.

• Revenue: Stripe, RevenueCat, App Store Connect, Lemon Squeezy, Paddle, Gumroad, Polar, Shopify
• Analytics: Plausible, Umami, Fathom, PostHog, Simple Analytics
• Hosting: Vercel, Netlify
• Newsletters: Kit, Buttondown, beehiiv
• Launches and social: YouTube, TikTok, Instagram, Bluesky, Product Hunt, Hacker News, npm
• Code: GitHub issues, commits and a plan file in your repo

KEEP, PIVOT OR KILL
After launch, Prodline watches the numbers against the targets you set. When the observe phase ends it suggests a verdict, so you decide on data instead of a feeling.

A STREAK WORTH KEEPING
Tick off goals, earn XP and keep your streak alive. A weekly wrap shows what you shipped. Home Screen and Lock Screen widgets and a deadline Live Activity keep the next checkpoint in sight.

ON YOUR MAC TOO
A native Mac app with a dashboard, an activity feed, a calendar of every deadline and a menu bar item. iCloud keeps your iPhone and Mac in step.

PRIVATE BY DESIGN
No account, no ads, no tracking. Your projects live on your devices and in your own iCloud. API keys stay in your Keychain and the app talks to each service directly.

Free, with no in-app purchases.
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

## Part 2: Screenshots

| Folder | Size | Upload to |
|---|---|---|
| `marketing/app-store/iphone-6.1/` | 1206 × 2622 | iPhone 6.1" display (**required**) |
| `marketing/app-store/iphone-6.9/` | 1320 × 2868 | iPhone 6.9" display |
| `marketing/app-store/mac/` | 2880 × 1800 | Mac (**required** for the Mac app) |

iPhone Duo screenshots are optional until April 2027; skip them for 1.0.

### iPhone (6 frames, in this order)

Each one is the real screen in a drawn iPhone 17 Pro (silver), lit from the top left, on a gradient in the color of the project it shows: green, blue, orange, indigo, purple, teal.

| # | Headline | Subline | Screen |
|---|---|---|---|
| 1 | Finish what you start. | Every side project on a short clock. | Dash, Habit Hero in the carousel |
| 2 | Numbers that come in on their own. | Revenue and visitors, live from Stripe. | Tiny Invoice: timeline, traction chart, Stripe and Plausible connected |
| 3 | A deadline for every step. | Checkpoints, goals and a streak. | Plan: streak, week strip, today's checkpoints with goals |
| 4 | 25+ services, connected. | Your keys stay in your Keychain. | The integration picker |
| 5 | Keep, pivot or kill. | Decide on numbers, not on a feeling. | Pixel Quest's decision, targets met, Keep suggested |
| 6 | Always in sight. | Your next deadline on the Home Screen. | Widgets on a neutral Home Screen |

### Mac (5 frames)

| # | Headline | Screen |
|---|---|---|
| 1 | Your week at a glance. | Dash: stats, Up next, Activity |
| 2 | Live numbers for every project. | Tiny Invoice's project page |
| 3 | Every deadline in one place. | Plan: agenda and calendar |
| 4 | One click away. | The menu bar panel on a desktop |
| 5 | Plan a build in a minute. | The create-project flow |

### The demo data behind them

`-PRODLINE_STORE YES` (DEBUG builds only) loads five projects into an in-memory store, so nothing reaches iCloud, and switches syncing off so the screens hold still. Covers are logos drawn by `design/make_demo_logos.swift`.

| Project | Phase | Connected | Numbers |
|---|---|---|---|
| Tiny Invoice | Observing, day 12 | Stripe, Plausible | $1,240 revenue · 3,180 visits · 46 sales |
| Pixel Quest | Observing, day 26, targets met | App Store Connect, YouTube, TikTok | 2,860 downloads · 41.2K views · 312 followers |
| Habit Hero | Building, day 9 | App Store Connect, RevenueCat | 86 downloads · 14 trials · $38 |
| Side Shop | Building, day 3 | Shopify, Plausible | 180 visits |
| Moonlog | Observing again after a Keep | Kit, Bluesky | 1,920 subscribers |

### Rebuilding them

1. iPhone 17 Pro simulator, status bar set with `xcrun simctl status_bar <sim> override --time 9:41 --batteryState discharging --batteryLevel 100`.
2. Shots with `-PRODLINE_STORE YES -PRODLINE_NOLAUNCH YES` plus: nothing (Dash), `-PRODLINE_OPEN "Tiny Invoice"` (scrolled to Traction), `-PRODLINE_TAB plan`, `-PRODLINE_OPEN "Tiny Invoice" -PRODLINE_SHEET picker`, `-PRODLINE_OPEN "Pixel Quest" -PRODLINE_SHEET verdict`, `-PRODLINE_SHEET board`. Save as dash, traction, plan, picker, verdict, board.png.
3. Mac: the same argument plus `-config.appearance light`; window captures of Dash, `-PRODLINE_OPEN "Tiny Invoice"`, `-PRODLINE_TAB plan`, `-PRODLINE_CREATE YES`; with `-PRODLINE_SNAPSHOT <path>` the snapshot writer adds the menu panel, the menu bar logo and the project cards.
4. `design/make_store_art.swift` composes the iPhone frames, the header and the search asset with SwiftUI (`/tmp/storeart <shots> marketing/app-store`); `design/make_mac_frames.swift` composes the Mac frames (usage at the top of each).

---

## Part 3: Header and search results assets

Optional, shown only on iOS 27 / iPadOS 27 and later. Upload them from the version page's "Header and Search Results" tab (or the Asset Library) once the app is approved; they're reviewed on their own. Rules: no prices, URLs, copyright signs, other platforms' logos or awards; 4+ content; no transparency (both files have none).

| File | Placement | Size |
|---|---|---|
| `marketing/app-store/header-21x9.png` | Product page header | 3840 × 1646 |
| `marketing/app-store/search-3x2.png` | Search results | 3840 × 2560 |

- **Header:** green, "Finish what you start." and a subline on the left, a hand holding the phone with Dash in the middle, two activity chips (a goal done from GitHub, the streak) on the right.
- **Search:** after Apple's own search example: green, "Finish what you start." top left, a short line bottom left, the hand-held phone with Dash on the right, its arm running off the bottom edge.
- Both use `design/mockup.png` (the hand-held mockup, 1600 x 1200). The script upscales it and swaps its screen for the sharp screenshot, keeping the fingers on top.
- **Later:** both slots also take 5–30 s video loops. A goal ticking itself off and the streak flame lighting would be the strongest one.

---

## Submitting

1. App Store Connect → Prodline → iOS: paste Part 1, upload `iphone-6.1` and `iphone-6.9`, select the build, answer age rating and privacy as above, "Add for Review".
2. Same app → macOS (add the platform if it isn't there): paste Part 1 again, upload `mac`, select the Mac build, "Add for Review".
3. Submit both together, release manually.
4. After approval: upload the header and search assets.
