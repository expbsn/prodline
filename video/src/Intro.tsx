import React from "react";
import { AbsoluteFill, continueRender, delayRender, Easing, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { ChunkyButton, CreateCard, Extruded, Flame, GoalRow, ProjectCard } from "./parts";
import { Accent, accents, display, H, theme, ui, W } from "./theme";

export const INTRO_FRAMES = 620;

// The display font, loaded before the first frame renders.
const fontHandle = delayRender("Afacad Flux");
new FontFace("Afacad Flux", `url(${staticFile("AfacadFlux.ttf")}) format("truetype")`, { weight: "100 1000" })
  .load()
  .then((f) => {
    document.fonts.add(f);
    continueRender(fontHandle);
  })
  .catch(() => continueRender(fontHandle));

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const inOut = Easing.bezier(0.45, 0, 0.2, 1);

// ── The camera ──────────────────────────────────────────────────────────────────────────────────
// Everything lives in one world (points, the project card centered at 0,0). The camera looks at a point,
// with a zoom and a tilt / orbit / roll; between keys it eases like a dolly on a track.
type Cam = { x: number; y: number; s: number; rx: number; ry: number; rz: number };
const KEYS: [number, Cam][] = [
  [92, { x: 0, y: 80, s: 1.5, rx: 30, ry: 0, rz: -4 }],
  [128, { x: 0, y: 10, s: 1.35, rx: 6, ry: -14, rz: 0 }],
  [148, { x: 0, y: 0, s: 1.3, rx: 4, ry: 0, rz: 0 }],
  // The checkpoint below the card.
  [172, { x: 0, y: 255, s: 1.05, rx: 18, ry: 10, rz: -2 }],
  [214, { x: 0, y: 290, s: 1.14, rx: 12, ry: -6, rz: 1 }],
  // The streak.
  [240, { x: 12, y: 550, s: 1.85, rx: 0, ry: -22, rz: 3 }],
  [290, { x: 0, y: 565, s: 2.05, rx: -6, ry: -8, rz: 0 }],
  // Shipping.
  [314, { x: 0, y: 880, s: 1.32, rx: 34, ry: 0, rz: 0 }],
  [346, { x: 0, y: 815, s: 1.18, rx: 10, ry: 8, rz: -2 }],
  // The numbers.
  [372, { x: 0, y: 1110, s: 0.95, rx: 22, ry: 18, rz: 0 }],
  [418, { x: 0, y: 1110, s: 1.04, rx: 10, ry: -16, rz: 0 }],
  // Pull back: everything goes back into the card.
  [446, { x: 0, y: 540, s: 0.42, rx: 6, ry: 0, rz: 0 }],
  [482, { x: 0, y: 0, s: 1.3, rx: 10, ry: 0, rz: 0 }],
  // The flipbook, then into the blank card.
  [548, { x: 0, y: 0, s: 1.42, rx: 14, ry: 0, rz: 0 }],
  [566, { x: 0, y: 0, s: 1.45, rx: 0, ry: 0, rz: 0 }],
];

function camAt(frame: number, follow: Cam): Cam {
  if (frame <= KEYS[0][0]) return follow;
  for (let i = 0; i < KEYS.length - 1; i++) {
    const [f0, a] = KEYS[i];
    const [f1, b] = KEYS[i + 1];
    if (frame <= f1) {
      const t = inOut(Math.min(1, Math.max(0, (frame - f0) / (f1 - f0))));
      const m = (p: number, q: number) => p + (q - p) * t;
      return { x: m(a.x, b.x), y: m(a.y, b.y), s: m(a.s, b.s), rx: m(a.rx, b.rx), ry: m(a.ry, b.ry), rz: m(a.rz, b.rz) };
    }
  }
  const last = KEYS[KEYS.length - 1][1];
  // Into the blank card: the zoom accelerates until the card is all you see.
  const z = interpolate(frame, [566, 612], [last.s, 16], { ...clamp, easing: Easing.in(Easing.cubic) });
  return { ...last, s: z };
}

// The dotted line's route across the floor, ending at the bottom of the card.
const ROUTE = { a: { x: -520, y: 1250 }, b: { x: -640, y: 700 }, c: { x: 320, y: 640 }, d: { x: 0, y: 150 } };
function routeAt(u: number) {
  const v = 1 - u;
  const { a, b, c, d } = ROUTE;
  return {
    x: v * v * v * a.x + 3 * v * v * u * b.x + 3 * v * u * u * c.x + u * u * u * d.x,
    y: v * v * v * a.y + 3 * v * v * u * b.y + 3 * v * u * u * c.y + u * u * u * d.y,
  };
}

// Where each step sits below the card.
const Y = { panel: 300, flame: 560, ship: 830, numbers: 1110 };

const flipbook: { name: string; cover?: string; accent: Accent }[] = [
  { name: "Pixel Quest", cover: "pixel-quest.jpg", accent: accents.purple },
  { name: "Side Shop", cover: "side-shop.jpg", accent: accents.charcoal },
  { name: "Kite", accent: accents.orange },
  { name: "Recipe Box", accent: { base: "#1CB0F6", dark: "#1592CC", on: "#FFFFFF" } },
  { name: "Trail Map", accent: { base: "#FF4B4B", dark: "#D23A3A", on: "#FFFFFF" } },
  { name: "Lingo", accent: { base: "#CE82FF", dark: "#A65FD6", on: "#FFFFFF" } },
  { name: "Budget", accent: { base: "#2BC8A8", dark: "#1F9E84", on: "#FFFFFF" } },
  { name: "Focus", accent: accents.gold },
  { name: "Postcard", accent: { base: "#5850EC", dark: "#433CC0", on: "#FFFFFF" } },
];

export const Intro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const sp = (start: number, damping = 14, stiffness = 120) => spring({ frame: frame - start, fps, config: { damping, stiffness } });
  const time = frame / fps;

  // ── 1 · follow shot ──
  const u = interpolate(frame, [0, 92], [0, 1], { ...clamp, easing: Easing.bezier(0.3, 0.05, 0.35, 1) });
  const head = routeAt(u);
  const follow: Cam = {
    x: head.x,
    y: head.y - 60,
    s: interpolate(frame, [0, 92], [1.9, 1.5], clamp),
    rx: interpolate(frame, [0, 92], [52, 30], clamp),
    ry: 0,
    rz: interpolate(frame, [0, 92], [-12, -4], clamp),
  };
  let cam = camAt(frame, follow);
  // Zoom punches on the beats (ticks, ignition, the press).
  const punch = (f: number, amount = 0.06) => amount * Math.sin(Math.PI * interpolate(frame, [f, f + 12], [0, 1], clamp));
  cam = { ...cam, s: cam.s * (1 + punch(178) + punch(194) + punch(210) + punch(252, 0.1) + punch(320, 0.08) + punch(330, 0.06)) };

  // ── 2 · the flip ──
  const flip = interpolate(sp(100, 13, 90), [0, 1], [0, 180]);
  // ── 3 · the steps ──
  const panelIn = sp(150, 15, 120);
  const ticks = [178, 194, 210].map((f) => interpolate(frame, [f, f + 8], [0, 1], clamp));
  const flameIn = sp(222, 16, 120);
  const flameGrow = frame < 252 ? interpolate(frame, [224, 252], [0.05, 0.3], clamp) : 0.3 + 0.7 * sp(252, 7, 140);
  const flameBright = interpolate(frame, [252, 262], [0, 1], clamp);
  const streak = frame >= 272 ? 3 : 2;
  const shipIn = sp(298, 15, 130);
  const press = interpolate(frame, [316, 320, 326], [0, 1, 0], clamp);
  const early = sp(328, 9, 160);
  const stats = [362, 372, 382].map((f) => sp(f, 12, 120));
  // ── 4 · back into the card ──
  const cram = (start: number) => interpolate(frame, [start, start + 26], [0, 1], { ...clamp, easing: Easing.in(Easing.cubic) });
  const absorbed = [cram(420), cram(428), cram(436), cram(444)];
  const pulse = 0.05 * [446, 454, 462, 470].reduce((a, f) => a + Math.sin(Math.PI * interpolate(frame, [f, f + 10], [0, 1], clamp)), 0);
  // ── 5 · flipbook ──
  const flipStarts: number[] = [];
  let at = 488;
  for (let i = 0; i <= flipbook.length; i++) {
    flipStarts.push(at);
    at += Math.max(4, 13 - i * 1.4);
  }
  const pageTurn = (i: number) => interpolate(frame, [flipStarts[i], flipStarts[i] + 15], [0, 1], { ...clamp, easing: Easing.inOut(Easing.quad) });

  // Shallow depth of field: whatever's far from where the camera looks goes soft.
  const dof = (y: number) => (frame < 140 || frame > 420 ? 0 : Math.min(7, Math.max(0, (Math.abs(y - cam.y) - 150) / 45)));
  const gridOpacity = interpolate(frame, [70, 112], [1, 0], clamp);

  const at3 = (x: number, y: number, extra = ""): React.CSSProperties => ({
    position: "absolute",
    left: x,
    top: y,
    transform: `translate(-50%, -50%) ${extra}`,
  });
  // Elements flying back into the card.
  const intoCard = (y: number, k: number) => `translateY(${-y * k}px) scale(${1 - 0.85 * k})`;

  return (
    <AbsoluteFill style={{ background: theme.background, overflow: "hidden" }}>
      <div style={{ width: W, height: H, zoom: 3, position: "relative", overflow: "hidden" }}>
        <div style={{ position: "absolute", left: W / 2, top: H / 2, width: 0, height: 0, perspective: 1300 }}>
          <div
            style={{
              position: "absolute",
              transformStyle: "preserve-3d",
              transformOrigin: "0 0",
              transform: `rotateX(${cam.rx}deg) rotateY(${cam.ry}deg) rotateZ(${cam.rz}deg) scale(${cam.s}) translate(${-cam.x}px, ${-cam.y}px)`,
            }}
          >
            {/* The floor grid gives the follow shot its depth, then fades away. */}
            {gridOpacity > 0 && (
              <svg width={2600} height={2200} style={{ position: "absolute", left: -1300, top: -500, opacity: gridOpacity }}>
                {Array.from({ length: 33 }, (_, i) => (
                  <line key={`v${i}`} x1={i * 80} y1={0} x2={i * 80} y2={2200} stroke={theme.line} strokeWidth={1.5} />
                ))}
                {Array.from({ length: 28 }, (_, i) => (
                  <line key={`h${i}`} x1={0} y1={i * 80} x2={2600} y2={i * 80} stroke={theme.line} strokeWidth={1.5} />
                ))}
              </svg>
            )}

            {/* 1 · the dotted line, swallowed by the card's edge */}
            {frame < 110 &&
              Array.from({ length: 44 }, (_, i) => {
                const ui0 = u - i * 0.021;
                if (ui0 < 0) return null;
                const p = routeAt(ui0);
                if (p.y < 150) return null;
                return <div key={i} style={{ ...at3(p.x, p.y), width: 14, height: 14, borderRadius: 7, background: theme.ink }} />;
              })}

            {/* 2 · the card: "New project" flips around into the project */}
            {frame < 488 + 15 && (
              <div
                style={{
                  ...at3(0, 0, `scale(${1 + pulse})`),
                  width: 200,
                  height: 280,
                  transformStyle: "preserve-3d",
                  zIndex: 20,
                }}
              >
                <div
                  style={{
                    position: "absolute",
                    inset: 0,
                    transformStyle: "preserve-3d",
                    transform: `rotateY(${flip}deg)`,
                  }}
                >
                  <div style={{ position: "absolute", inset: 0, backfaceVisibility: "hidden", borderRadius: 23, boxShadow: "0 18px 26px rgba(0,0,0,0.14)" }}>
                    <CreateCard width={200} />
                  </div>
                  <div style={{ position: "absolute", inset: 0, backfaceVisibility: "hidden", transform: "rotateY(180deg)" }}>
                    <div
                      style={{
                        transformOrigin: "50% 0%",
                        transform: `rotateX(${-180 * pageTurn(0)}deg)`,
                        backfaceVisibility: "hidden",
                        borderRadius: 23,
                        boxShadow: "0 18px 26px rgba(0,0,0,0.14)",
                      }}
                    >
                      <div style={{ filter: `blur(${dof(0)}px)`, borderRadius: 23 }}>
                        <ProjectCard name="Habit Hero" cover="habit-hero.jpg" accent={accents.green} cornerLabel="Day" cornerValue="12" footnote="Building" />
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* 5 · the flipbook behind it: pages flip up and over, faster and faster, down to a blank card */}
            {frame >= 470 &&
              [...flipbook, null].map((c, i) => {
                const k = i + 1 < flipStarts.length ? pageTurn(i + 1) : 0;
                if (k >= 1) return null;
                const blank = c === null;
                const fadeEdge = blank ? interpolate(frame, [570, 596], [1, 0], clamp) : 1;
                return (
                  <div
                    key={i}
                    style={{
                      ...at3(0, 0, `translateZ(${-(i + 1) * 1.5}px) rotateX(${-180 * k}deg)`),
                      transformOrigin: "50% 0%",
                      zIndex: 10 - i,
                      width: 200,
                      height: 280,
                      backfaceVisibility: "hidden",
                      borderRadius: 23,
                      boxShadow: blank ? "none" : "0 12px 20px rgba(0,0,0,0.12)",
                    }}
                  >
                    {blank ? (
                      <div
                        style={{
                          width: 200,
                          height: 280,
                          borderRadius: 30 * (200 / 260),
                          background: theme.background,
                          boxShadow: `0 0 0 1.5px rgba(0,0,0,${0.06 * fadeEdge}), 0 14px 26px rgba(0,0,0,${0.1 * fadeEdge})`,
                        }}
                      />
                    ) : (
                      <ProjectCard name={c.name} cover={c.cover} accent={c.accent} cornerLabel="Day" cornerValue={`${3 + i * 2}`} footnote="Building" />
                    )}
                  </div>
                );
              })}

            {/* 3a · the checkpoint */}
            {frame >= 148 && absorbed[0] < 1 && (
              <div style={{ ...at3(0, Y.panel, intoCard(Y.panel, absorbed[0])), opacity: Math.min(1, panelIn * 1.4) * (1 - absorbed[0]) }}>
                <div
                  style={{
                    width: 330,
                    background: theme.card,
                    borderRadius: 26,
                    padding: 20,
                    boxSizing: "border-box",
                    boxShadow: "0 14px 30px rgba(0,0,0,0.08)",
                    transform: `translateY(${(1 - panelIn) * 70}px) rotateX(${(1 - panelIn) * -40}deg)`,
                    filter: `blur(${dof(Y.panel)}px)`,
                    position: "relative",
                  }}
                >
                  <div style={{ fontFamily: display, fontWeight: 750, fontSize: 22, color: theme.ink }}>Checkpoint 2</div>
                  <div style={{ fontFamily: ui, fontSize: 13, color: theme.secondary, marginTop: 2, marginBottom: 14 }}>
                    Due Friday · {ticks.filter((t) => t > 0.5).length}/3 goals
                  </div>
                  <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
                    {["Onboarding flow live", "Shareable streak card", "Push reminders"].map((g, i) => (
                      <GoalRow key={g} title={g} done={ticks[i]} accent={accents.green} />
                    ))}
                  </div>
                  {[178, 194, 210].map((f, i) => {
                    const d = frame - f;
                    if (d < 0 || d > 38) return null;
                    return (
                      <div
                        key={i}
                        style={{
                          position: "absolute",
                          right: 18,
                          top: 76 + i * 32 - interpolate(d, [0, 38], [0, 16], clamp),
                          opacity: interpolate(d, [0, 5, 28, 38], [0, 1, 1, 0], clamp),
                          transform: `scale(${0.6 + 0.4 * Math.min(1, d / 6)})`,
                          fontFamily: display,
                          fontWeight: 800,
                          fontSize: 17,
                          color: accents.gold.dark,
                        }}
                      >
                        +3 XP
                      </div>
                    );
                  })}
                </div>
              </div>
            )}

            {/* 3b · the streak */}
            {frame >= 220 && absorbed[1] < 1 && (
              <div
                style={{
                  ...at3(0, Y.flame, intoCard(Y.flame, absorbed[1])),
                  opacity: flameIn * (1 - absorbed[1]),
                  display: "flex",
                  flexDirection: "column",
                  alignItems: "center",
                  filter: `blur(${dof(Y.flame)}px)`,
                }}
              >
                <div style={{ width: 92, height: 120, transform: `translateY(${(1 - flameIn) * 40}px)` }}>
                  <Flame time={time} grow={flameGrow} bright={flameBright} width={92} />
                </div>
                <div style={{ marginTop: 14, textAlign: "center", opacity: interpolate(frame, [258, 268], [0, 1], clamp) }}>
                  <div style={{ fontFamily: display, fontWeight: 850, fontSize: 40, color: theme.ink, lineHeight: 1 }}>{streak}</div>
                  <div style={{ fontFamily: ui, fontWeight: 700, fontSize: 11, letterSpacing: 2, color: theme.secondary, marginTop: 2 }}>DAY STREAK</div>
                </div>
              </div>
            )}

            {/* 3c · shipping */}
            {frame >= 296 && absorbed[2] < 1 && (
              <div
                style={{
                  ...at3(0, Y.ship, intoCard(Y.ship, absorbed[2])),
                  opacity: shipIn * (1 - absorbed[2]),
                  display: "flex",
                  flexDirection: "column",
                  alignItems: "center",
                  gap: 18,
                  filter: `blur(${dof(Y.ship)}px)`,
                }}
              >
                <div style={{ transform: `perspective(600px) rotateX(${(1 - early) * 70}deg) scale(${0.5 + 0.5 * early})`, opacity: Math.min(1, early * 2), textAlign: "center" }}>
                  <Extruded text="4" size={110} accent={accents.green} />
                  <div style={{ marginTop: 4 }}>
                    <Extruded text="days early" size={28} accent={accents.green} weight={800} />
                  </div>
                </div>
                <div style={{ transform: `translateY(${(1 - shipIn) * 60}px)` }}>
                  <ChunkyButton title="Let's ship" accent={accents.green} pressed={press} width={260} />
                </div>
              </div>
            )}

            {/* 3d · the numbers */}
            {frame >= 358 && absorbed[3] < 1 && (
              <div
                style={{
                  ...at3(0, Y.numbers, intoCard(Y.numbers, absorbed[3])),
                  opacity: 1 - absorbed[3],
                  display: "flex",
                  gap: 26,
                  alignItems: "flex-end",
                  filter: `blur(${dof(Y.numbers)}px)`,
                }}
              >
                {[
                  { v: "+1,240", l: "visits", a: accents.green },
                  { v: "+$612", l: "revenue", a: accents.gold },
                  { v: "312", l: "downloads", a: accents.purple },
                ].map((s, i) => (
                  <div
                    key={s.l}
                    style={{
                      textAlign: "center",
                      opacity: Math.min(1, stats[i] * 1.5),
                      transform: `translateY(${(1 - stats[i]) * 50}px) perspective(500px) rotateX(${(1 - stats[i]) * 75}deg)`,
                    }}
                  >
                    <Extruded text={s.v} size={i === 0 ? 46 : 38} accent={s.a} />
                    <div style={{ fontFamily: ui, fontWeight: 600, fontSize: 13, color: theme.secondary, marginTop: 4 }}>{s.l}</div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};
