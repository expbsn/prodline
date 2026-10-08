import React from "react";
import { AbsoluteFill, continueRender, delayRender, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig, Easing } from "remotion";
import { ChunkyButton, Extruded, Flame, GoalRow, ProjectCard } from "./parts";
import { accents, display, H, theme, ui, W } from "./theme";

export const INTRO_FRAMES = 470;

// The display font, loaded before the first frame renders.
const fontHandle = delayRender("Afacad Flux");
const font = new FontFace("Afacad Flux", `url(${staticFile("AfacadFlux.ttf")}) format("truetype")`, { weight: "100 1000" });
font
  .load()
  .then((f) => {
    document.fonts.add(f);
    continueRender(fontHandle);
  })
  .catch(() => continueRender(fontHandle));

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const ease = Easing.bezier(0.33, 0, 0.2, 1);

// The logo, exactly as LogoGeometry draws it (1024-unit icon space): one stroke up the stem, round the bowl,
// out along the crossbar, with the dotted line coming in from below and leaving to the left.
const LOGO = {
  stroke: 100,
  stemX: 490,
  barY: 490,
  spacing: 160,
  main: "M 490 630 L 490 390 C 490 250 552 190 672 190 C 792 190 856 262 856 342 C 856 430 792 490 700 490 L 402 490",
  center: { x: 481, y: 558 },
};

const cards = [
  { name: "Pixel Quest", cover: "pixel-quest.jpg", accent: accents.purple, day: "5", foot: "Building" },
  { name: "Habit Hero", cover: "habit-hero.jpg", accent: accents.green, day: "12", foot: "Building" },
  { name: "Side Shop", cover: "side-shop.jpg", accent: accents.charcoal, day: "9", foot: "Observing" },
];

export const Intro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const sp = (start: number, damping = 14, stiffness = 120, mass = 1) =>
    spring({ frame: frame - start, fps, config: { damping, stiffness, mass } });
  const time = frame / fps;

  // ── 1–2: dotted line rises, carves the "p", leaves to the left ───────────────────────────────
  const k = 150 / 850; // mark 150 pt wide
  const markX = W / 2 - LOGO.center.x * k;
  const markY = H / 2 - 40 - LOGO.center.y * k;
  const bottomInLogo = (H - markY) / k + LOGO.spacing; // just below the screen, in logo units
  const head = interpolate(frame, [0, 52], [bottomInLogo, 630], { ...clamp, easing: Easing.bezier(0.2, 0.6, 0.3, 1) });
  // After arriving, the dots keep flowing into the stem while the stroke draws, until the last one is in.
  const DOTS = 9;
  const flow = interpolate(frame, [52, 112], [0, DOTS * LOGO.spacing], clamp);
  const carve = interpolate(frame, [52, 112], [0, 1], { ...clamp, easing: Easing.inOut(Easing.quad) });
  const exit = interpolate(frame, [108, 150], [0, 1], { ...clamp, easing: Easing.in(Easing.quad) });
  const markOut = interpolate(frame, [132, 160], [1, 0], clamp);
  const markScale = interpolate(frame, [132, 160], [1, 0.55], { ...clamp, easing: ease });

  // ── 3: the mark becomes a card; the cards fan out ──────────────────────────────────────────────
  const cardIn = sp(138, 13, 110);
  const fan = sp(176, 12, 100);
  // ── 4: focus on Habit Hero, goals tick, flame lights ───────────────────────────────────────────
  const focus = sp(238, 16, 110);
  const panelIn = sp(246, 15, 120);
  const ticks = [266, 286, 306].map((f) => interpolate(frame, [f, f + 8], [0, 1], clamp));
  const flameGrow = frame < 312 ? 0.05 : 0.05 + 0.95 * sp(312, 7, 140);
  const flameOn = interpolate(frame, [312, 322], [0, 1], clamp);
  // ── 5: ship ────────────────────────────────────────────────────────────────────────────────────
  const buttonIn = sp(318, 15, 140);
  const press = interpolate(frame, [334, 338, 344], [0, 1, 0], clamp);
  const launch = interpolate(frame, [342, 372], [0, 1], { ...clamp, easing: Easing.in(Easing.cubic) });
  const numbers = sp(362, 12, 120);
  const stamp = sp(382, 10, 220);
  // ── 6: settle into the Welcome screen ──────────────────────────────────────────────────────────
  const outro = interpolate(frame, [398, 414], [0, 1], { ...clamp, easing: ease });
  const welcome = sp(404, 15, 100);
  const welcomeFan = sp(420, 13, 90);

  const showLogo = frame < 162;
  const showCards = frame >= 136 && frame < 400;

  // The wash of the focused project's color behind the cards, as on Dash.
  const washOpacity = interpolate(frame, [150, 190, 360, 400], [0, 0.22, 0.22, 0], clamp);

  return (
    <AbsoluteFill style={{ background: theme.background }}>
      <div style={{ width: W, height: H, zoom: 3, position: "relative", overflow: "hidden" }}>
        <div
          style={{
            position: "absolute",
            left: -120,
            right: -120,
            top: 120,
            height: 640,
            background: `radial-gradient(closest-side, ${accents.green.base}${Math.round(washOpacity * 255).toString(16).padStart(2, "0")}, transparent)`,
          }}
        />

        {/* 1–2 · the mark */}
        {showLogo && (
          <svg width={W} height={H} style={{ position: "absolute", inset: 0, opacity: markOut }}>
            <g
              transform={`translate(${markX + (LOGO.center.x * k) * (1 - markScale)}, ${markY + (LOGO.center.y * k) * (1 - markScale)}) scale(${k * markScale})`}
            >
              {/* Dots rising up the stem, swallowed where the stroke begins. */}
              {Array.from({ length: DOTS }, (_, n) => {
                const y = head + n * LOGO.spacing - flow;
                return y >= 630 ? <circle key={n} cx={LOGO.stemX} cy={y} r={LOGO.stroke / 2} fill={theme.ink} /> : null;
              })}
              <path
                d={LOGO.main}
                pathLength={1}
                fill="none"
                stroke={theme.ink}
                strokeWidth={LOGO.stroke}
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeDasharray="1 1"
                strokeDashoffset={1 - carve}
              />
              {/* Out to the left along the crossbar. */}
              {exit > 0 &&
                Array.from({ length: 5 }, (_, n) => {
                  const x = 402 - LOGO.spacing * (n + 1) * 0.9 - exit * 1400;
                  const o = interpolate(x, [-900, 300], [0, 1], clamp);
                  return <circle key={`e${n}`} cx={x} cy={LOGO.barY} r={LOGO.stroke / 2} fill={theme.ink} opacity={o} />;
                })}
            </g>
          </svg>
        )}

        {/* 3–5 · the cards */}
        {showCards &&
          cards.map((c, i) => {
            const side = i - 1;
            const center = side === 0;
            const lift = center ? -110 * focus - 900 * launch : 0;
            const rot = side * 9 * fan * (1 - focus) + (center ? -10 * launch : side * 18 * focus);
            const x = side * 82 * fan + side * 140 * focus;
            const y = Math.abs(side) * 18 * fan + lift;
            const scale = (center ? 0.4 + 0.6 * cardIn : 0.88 * fan) * (center ? 1 - 0.12 * focus : 1);
            const opacity = center ? Math.min(1, cardIn * 1.4) : fan * (1 - focus);
            // A little 3D: the card tips up as it arrives.
            const tilt = center ? (1 - cardIn) * 35 : 0;
            return (
              <div
                key={c.name}
                style={{
                  position: "absolute",
                  left: W / 2 - 100,
                  top: H / 2 - 40 - 140,
                  zIndex: center ? 2 : 1,
                  opacity,
                  transform: `perspective(900px) translate(${x}px, ${y}px) rotate(${rot}deg) rotateX(${tilt}deg) scale(${scale})`,
                  transformOrigin: "50% 100%",
                  filter: `drop-shadow(0 ${10 + 6 * fan}px ${16 + 8 * fan}px rgba(0,0,0,${0.12 + 0.05 * fan}))${!center ? ` blur(${4 * focus}px)` : ""}`,
                }}
              >
                <ProjectCard name={c.name} cover={c.cover} accent={c.accent} cornerLabel="Day" cornerValue={c.day} footnote={c.foot} width={200} />
              </div>
            );
          })}

        {/* 4 · the checkpoint panel */}
        {frame >= 244 && frame < 400 && (
          <div
            style={{
              position: "absolute",
              left: 24,
              right: 24,
              top: 470 + (1 - panelIn) * 420 + launch * 60,
              opacity: Math.min(1, panelIn * 1.5) * Math.max(0, 1 - launch * 2.5),
              background: theme.card,
              borderRadius: 26,
              padding: 20,
              boxShadow: "0 10px 30px rgba(0,0,0,0.08)",
            }}
          >
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 14 }}>
              <div>
                <div style={{ fontFamily: display, fontWeight: 750, fontSize: 22, color: theme.ink }}>Checkpoint 2</div>
                <div style={{ fontFamily: ui, fontSize: 13, color: theme.secondary, marginTop: 2 }}>
                  Due Friday · {ticks.filter((t) => t > 0.5).length}/3 goals
                </div>
              </div>
              <div style={{ display: "flex", alignItems: "flex-end", gap: 4 }}>
                <div style={{ width: 30, height: 39, opacity: flameOn || 0.0001 }}>
                  <Flame time={time} grow={flameGrow} bright={flameOn} width={30} />
                </div>
                <div style={{ fontFamily: display, fontWeight: 800, fontSize: 22, color: flameOn > 0.5 ? theme.flame : theme.tertiary, marginBottom: 2 }}>
                  {flameOn > 0.5 ? 3 : 2}
                </div>
              </div>
            </div>
            <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
              {["Onboarding flow live", "Shareable streak card", "Push reminders"].map((g, i) => (
                <GoalRow key={g} title={g} done={ticks[i]} accent={accents.green} />
              ))}
            </div>
            {/* +3 XP for every tick, floating up out of the panel */}
            {ticks.map((t, i) => {
              const f = frame - [266, 286, 306][i];
              if (f < 0 || f > 40) return null;
              const up = interpolate(f, [0, 40], [0, -18], { ...clamp, easing: Easing.out(Easing.cubic) });
              const o = interpolate(f, [0, 6, 28, 40], [0, 1, 1, 0], clamp);
              return (
                <div
                  key={i}
                  style={{
                    position: "absolute",
                    right: 20,
                    top: 82 + i * 32 + up,
                    opacity: o,
                    fontFamily: display,
                    fontWeight: 800,
                    fontSize: 18,
                    color: accents.gold.dark,
                    textShadow: `0.5px 1px 0 ${accents.gold.dark}55`,
                  }}
                >
                  +3 XP
                </div>
              );
            })}
          </div>
        )}

        {/* 5 · ship */}
        {frame >= 316 && frame < 400 && (
          <div style={{ position: "absolute", left: 24, bottom: 54 - (1 - buttonIn) * 140, opacity: buttonIn * (1 - outro) }}>
            <ChunkyButton title="Let's ship" accent={accents.green} pressed={press} />
          </div>
        )}
        {frame >= 360 && frame < 416 && (
          <div
            style={{
              position: "absolute",
              left: 0,
              right: 0,
              top: 230,
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              gap: 6,
              opacity: 1 - outro,
              transform: `translateY(${(1 - numbers) * 120 - outro * 40}px)`,
            }}
          >
            <div style={{ transform: `perspective(700px) rotateX(${(1 - numbers) * 50}deg)` }}>
              <Extruded text="+1,240" size={84} accent={accents.green} />
            </div>
            <div style={{ fontFamily: ui, fontWeight: 600, fontSize: 17, color: theme.secondary, marginBottom: 14 }}>visits</div>
            <div style={{ transform: `perspective(700px) rotateX(${(1 - numbers) * 50}deg)` }}>
              <Extruded text="+$612" size={64} accent={accents.gold} />
            </div>
            <div style={{ fontFamily: ui, fontWeight: 600, fontSize: 17, color: theme.secondary }}>revenue</div>
            <div
              style={{
                marginTop: 26,
                opacity: Math.min(1, stamp * 2),
                transform: `rotate(${-8 + 0 * stamp}deg) scale(${1.8 - 0.8 * stamp})`,
                background: accents.green.base,
                color: "white",
                fontFamily: display,
                fontWeight: 800,
                fontSize: 26,
                letterSpacing: 3,
                padding: "8px 22px",
                borderRadius: 16,
                boxShadow: `0 5px 0 ${accents.green.dark}`,
              }}
            >
              KEEP
            </div>
          </div>
        )}

        {/* 6 · the Welcome screen */}
        {frame >= 400 && (
          <div style={{ position: "absolute", inset: 0, opacity: Math.min(1, welcome * 1.3) }}>
            <div style={{ position: "absolute", left: 0, right: 0, top: 96, height: 340 }}>
              {[0, 1, 2].map((i) => {
                const c = [cards[1], cards[0], cards[2]][i];
                const side = i - 1;
                return (
                  <div
                    key={c.name}
                    style={{
                      position: "absolute",
                      left: W / 2 - 100,
                      top: 30,
                      zIndex: i,
                      transform: `translate(${side * 30 * welcomeFan}px, ${Math.abs(side) * 10 * welcomeFan + (1 - welcome) * 60}px) rotate(${side * 7 * welcomeFan}deg)`,
                      transformOrigin: "50% 100%",
                      filter: "drop-shadow(0 10px 16px rgba(0,0,0,0.12))",
                    }}
                  >
                    <ProjectCard name={c.name} cover={c.cover} accent={c.accent} cornerLabel="Day" cornerValue={c.day} footnote={c.foot} width={200} />
                  </div>
                );
              })}
            </div>
            <div style={{ position: "absolute", left: 24, right: 24, top: 470, transform: `translateY(${(1 - welcome) * 30}px)` }}>
              <div style={{ fontFamily: ui, fontWeight: 600, fontSize: 12, letterSpacing: 3, textTransform: "uppercase", color: theme.secondary }}>
                Welcome to
              </div>
              <div style={{ fontFamily: display, fontWeight: 800, fontSize: 60, color: theme.ink, lineHeight: 1.05, marginTop: 4 }}>Prodline</div>
              <div style={{ fontFamily: ui, fontSize: 19, color: theme.inkSoft, marginTop: 14, lineHeight: 1.3 }}>
                Ship a project every cycle, watch its numbers come in, and keep the streak going.
              </div>
            </div>
          </div>
        )}
      </div>
    </AbsoluteFill>
  );
};
