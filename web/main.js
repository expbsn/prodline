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

// Nav gets a hairline once the page moves.
const nav = document.querySelector(".nav");
const onScroll = () => nav.classList.toggle("scrolled", scrollY > 8);
addEventListener("scroll", onScroll, { passive: true });
onScroll();

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
