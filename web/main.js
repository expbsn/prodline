// Prodline landing page: reveals on scroll, hand-drawn lines, the waitlist form.

const RELAY = "https://prodline-relay.prodline-relay.workers.dev";

// Blur-in reveals and lines that draw themselves when they come into view.
const seen = new IntersectionObserver((entries) => {
  for (const e of entries) {
    if (!e.isIntersecting) continue;
    e.target.classList.add("in");
    seen.unobserve(e.target);
  }
}, { rootMargin: "0px 0px -12% 0px", threshold: 0.12 });
document.querySelectorAll("[data-reveal], .draw").forEach((el) => seen.observe(el));

// How it works: a dotted trail through the step numbers that draws itself as you scroll, numbers that
// light up when it reaches them, and stickers that drift at their own speed.
const flow = document.querySelector(".flow");
if (flow) {
  const svg = flow.querySelector(".trail");
  const ghost = svg.querySelector(".trail-ghost");
  const dots = svg.querySelector(".trail-dots");
  const reveal = svg.querySelector(".trail-reveal");
  const head = svg.querySelector(".trail-head");
  const nodes = [...flow.querySelectorAll(".node")];
  const stickers = [...flow.querySelectorAll(".stk")];
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  let length = 0;
  let nodeLengths = [];

  // S-bends between the node centres (in the section's own coordinates), with a lead-in and a tail.
  const build = () => {
    const box = flow.getBoundingClientRect();
    const pts = nodes.map((n) => {
      const r = n.getBoundingClientRect();
      return { x: r.left + r.width / 2 - box.left, y: r.top + r.height / 2 - box.top };
    });
    if (!pts.length) return;
    svg.setAttribute("viewBox", `0 0 ${box.width} ${box.height}`);
    const start = { x: pts[0].x - 40, y: pts[0].y - 280 };
    const end = { x: pts.at(-1).x + 220, y: Math.min(box.height, pts.at(-1).y + 380) };
    const all = [start, ...pts, end];
    // The text sits to the right of each number, so the trail leaves and enters every number from the left
    // and never runs through a paragraph; the phones simply cover it where it crosses them.
    const swing = Math.min(220, box.width * 0.16);
    let d = `M ${start.x} ${start.y}`;
    for (let i = 1; i < all.length; i++) {
      const a = all[i - 1], b = all[i], dy = b.y - a.y;
      const out = i === 1 ? 0 : swing, into = i === all.length - 1 ? 0 : swing;
      d += ` C ${a.x - out} ${a.y + dy * 0.45}, ${b.x - into} ${b.y - dy * 0.45}, ${b.x} ${b.y}`;
    }
    for (const p of [ghost, dots, reveal]) p.setAttribute("d", d);
    length = dots.getTotalLength();
    reveal.style.strokeDasharray = `${length}`;
    // where along the trail each node sits
    nodeLengths = pts.map((p) => lengthAtY(p.y));
    update();
  };

  // The trail only ever goes down, so the point at a given height can be found by bisection.
  const lengthAtY = (y) => {
    let lo = 0, hi = length;
    for (let i = 0; i < 24; i++) {
      const mid = (lo + hi) / 2;
      if (dots.getPointAtLength(mid).y < y) lo = mid; else hi = mid;
    }
    return (lo + hi) / 2;
  };

  const update = () => {
    if (!length) return;
    const box = flow.getBoundingClientRect();
    const line = still ? Infinity : innerHeight * 0.62 - box.top;   // the trail's tip follows this height
    const l = line === Infinity ? length : Math.max(0, Math.min(length, lengthAtY(line)));
    reveal.style.strokeDashoffset = `${length - l}`;
    const p = dots.getPointAtLength(l);
    head.setAttribute("cx", p.x);
    head.setAttribute("cy", p.y);
    head.style.opacity = l > 2 && l < length - 2 ? 1 : 0;
    nodes.forEach((n, i) => n.classList.toggle("lit", l >= nodeLengths[i] - 4));
    if (!still) {
      for (const s of stickers) {
        const r = s.getBoundingClientRect();
        const off = (r.top + r.height / 2 - innerHeight / 2) * -(Number(getComputedStyle(s).getPropertyValue("--p")) || 0.15);
        // capped, so a sticker never drifts out of its own step (e.g. on a short phone screen)
        s.style.setProperty("--py", `${Math.max(-48, Math.min(48, off)).toFixed(1)}px`);
      }
    }
  };

  let queued = false;
  addEventListener("scroll", () => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => { queued = false; update(); });
  }, { passive: true });
  addEventListener("resize", build);
  flow.querySelectorAll("img").forEach((img) => img.complete || img.addEventListener("load", build, { once: true }));
  document.fonts?.ready.then(build);
  build();
}

// Integrations: the names stand on a ring (a cylinder) seen slightly from above. Sizes come from the
// screen width so the ring's sides always reach past both edges; the list repeats until it fills the
// circumference, spaced by each name's own width. Scrolling turns the ring.
const stage = document.querySelector(".ring-stage");
if (stage) {
  const ring = stage.querySelector(".ring");
  const names = [...ring.children].map((li) => li.textContent);
  const calm = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const TILT = 17;                       // degrees we look down onto the ring
  let items = [], R = 0, visible = false, t0 = performance.now();

  const build = () => {
    const vw = stage.clientWidth;
    const p = vw * 2.2;                  // perspective; with R0 below the sides project to ~0.6 vw
    const R0 = (0.6 * vw * p) / (p - 0.6 * vw);
    stage.style.setProperty("--ring-p", `${p}px`);
    const make = (text, hidden) => {
      const li = document.createElement("li");
      li.textContent = text;
      if (hidden) li.setAttribute("aria-hidden", "true");
      ring.append(li);
      return li;
    };
    // One full list, measured. The ring holds whole copies only (one, or two half a turn apart), so a name
    // never shows up again close to itself; if one copy doesn't fit (phones), the ring grows instead.
    const MIN_GAP = 64;
    ring.replaceChildren();
    const first = names.map((n) => ({ li: make(n, false), name: n }));
    const widths = first.map((it) => it.li.offsetWidth);   // layout width (3D transforms shrink measured boxes)
    const once = widths.reduce((a, b) => a + b, 0) + names.length * MIN_GAP;
    R = Math.max(R0, once / (2 * Math.PI));
    const circ = 2 * Math.PI * R;
    const copies = Math.max(1, Math.floor(circ / once));
    items = first.map((it, i) => ({ li: it.li, w: widths[i] }));
    for (let c = 1; c < copies; c++) names.forEach((n, i) => items.push({ li: make(n, true), w: widths[i] }));
    const used = widths.reduce((a, b) => a + b, 0) * copies;
    const gap = (circ - used) / items.length;
    const h = Math.round(Math.max(230, vw * 0.27));
    stage.style.setProperty("--ring-h", `${h}px`);
    // tilting drops the front of the ring by R·sin(tilt); lift it so the front lands low in the stage
    // and the sides rise towards its top edge
    stage.style.setProperty("--ring-top", `${Math.round(h * 0.62 - R * Math.sin((TILT * Math.PI) / 180))}px`);
    let at = 0;
    for (const it of items) {
      it.angle = ((at + it.w / 2) / circ) * 360;
      at += it.w + gap;
      it.li.style.transform = `rotateY(${it.angle}deg) translateZ(${R}px)`;
    }
    update(performance.now());
  };

  const update = (now) => {
    const spin = -(scrollY * 0.05) - (calm ? 0 : (now - t0) * 0.005);
    // move the ring back by R so the front name sits at the screen plane, tilt, then spin
    ring.style.transform = `translateZ(${-R}px) rotateX(${-TILT}deg) rotateY(${spin}deg)`;
    for (const it of items) {
      const facing = Math.cos(((it.angle + spin) * Math.PI) / 180);   // 1 front, 0 at the sides
      it.li.style.opacity = facing <= 0 ? 0 : (0.15 + 0.85 * facing ** 1.6).toFixed(3);
    }
  };

  const tick = (now) => { update(now); if (visible) requestAnimationFrame(tick); };
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; if (visible) requestAnimationFrame(tick); }).observe(stage);
  addEventListener("scroll", () => update(performance.now()), { passive: true });
  addEventListener("resize", build);
  document.fonts?.ready.then(build);
  build();
}

// Features: the revenue counts up the first time it's seen; the Live Activity's countdown ticks.
const count = document.querySelector(".t-numbers .count");
if (count) {
  const to = Number(count.dataset.to);
  new IntersectionObserver(([e], o) => {
    if (!e.isIntersecting) return;
    o.disconnect();
    const t0 = performance.now();
    const step = (now) => {
      const k = Math.min(1, (now - t0) / 1400);
      count.textContent = "$" + Math.round(to * (1 - (1 - k) ** 3)).toLocaleString("en-US");
      if (k < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }, { threshold: 0.4 }).observe(count);
}
const liveT = document.querySelector(".live-t");
if (liveT) {
  let left = 2 * 3600 - 1;
  const show = () => {
    const h = Math.floor(left / 3600), m = Math.floor((left % 3600) / 60), sec = left % 60;
    liveT.textContent = `${h}:${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}`;
  };
  show();
  setInterval(() => { left = left > 0 ? left - 1 : 2 * 3600 - 1; show(); }, 1000);
}

// Nav: a pill slides to the link of the section you're looking at.
const navLinks = [...document.querySelectorAll(".links a[href^='#']")];
if (navLinks.length) {
  const bar = document.querySelector(".links");
  const pill = document.createElement("span");
  pill.className = "pill-ind";
  bar.prepend(pill);
  const targets = navLinks.map((a) => document.querySelector(a.getAttribute("href")));
  let current = -1;
  const place = () => {
    const line = innerHeight * 0.4;
    let i = -1;
    targets.forEach((t, k) => { if (t && t.getBoundingClientRect().top <= line) i = k; });
    // past the end of the last tracked section (e.g. the join card), nothing is current
    const last = targets.at(-1);
    if (i === targets.length - 1 && last.getBoundingClientRect().bottom < line) i = -1;
    if (i === current) return;
    current = i;
    navLinks.forEach((a, k) => a.classList.toggle("on", k === i));
    if (i < 0) { pill.style.opacity = 0; return; }
    const a = navLinks[i], b = bar.getBoundingClientRect(), r = a.getBoundingClientRect();
    pill.style.opacity = 1;
    pill.style.width = `${r.width}px`;
    pill.style.transform = `translateX(${r.left - b.left}px)`;
  };
  addEventListener("scroll", place, { passive: true });
  addEventListener("resize", () => { current = -2; place(); });
  place();
}

// Waitlist
const form = document.getElementById("waitlist");
const note = document.getElementById("form-note");
const button = form?.querySelector("button");
form?.addEventListener("submit", async (e) => {
  e.preventDefault();
  const email = form.email.value.trim();
  form.classList.remove("bad");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
    void form.offsetWidth;
    form.classList.add("bad");
    note.className = "fine err";
    note.textContent = "That email looks a little off.";
    return;
  }
  button.disabled = true;
  button.textContent = "…";
  try {
    const r = await fetch(`${RELAY}/waitlist`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email, website: form.website.value }),
    });
    if (!r.ok) throw new Error(String(r.status));
    const body = await r.json();
    note.className = "fine ok";
    note.textContent = body.already ? "You're already on the list. We haven't forgotten you." : "You're on the list. Keep that project warm.";
    button.textContent = "Done";
    form.email.value = "";
  } catch {
    note.className = "fine err";
    note.textContent = "Couldn't reach the list. Try again in a moment.";
    button.disabled = false;
    button.textContent = "Join";
  }
});
