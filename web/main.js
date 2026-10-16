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

// Integrations: each row is doubled so it can loop; scrolling slides the rows in opposite directions,
// with a slow drift of their own while they're on screen.
const marquees = [...document.querySelectorAll(".marquee")].map((m, i) => {
  const track = m.querySelector(".track");
  track.append(...[...track.children].map((li) => { const c = li.cloneNode(true); c.setAttribute("aria-hidden", "true"); return c; }));
  return { m, track, dir: m.classList.contains("rev") ? 1 : -1, phase: i * 180 };
});
if (marquees.length) {
  const calm = matchMedia("(prefers-reduced-motion: reduce)").matches;
  let visible = false, t0 = performance.now();
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; if (visible) requestAnimationFrame(tick); })
    .observe(document.querySelector(".intg"));
  function tick(now) {
    for (const { track, dir, phase } of marquees) {
      const half = track.scrollWidth / 2;
      const drift = calm ? 0 : (now - t0) * 0.018;
      let x = (scrollY * 0.45 + drift + phase) * dir;
      x = ((x % half) + half) % half;          // 0…half, then wrap
      track.style.transform = `translate3d(${-x}px, 0, 0)`;
    }
    if (visible) requestAnimationFrame(tick);
  }
}

// Waitlist
const form = document.getElementById("waitlist");
const note = document.getElementById("form-note");
const button = form.querySelector("button");
form.addEventListener("submit", async (e) => {
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
