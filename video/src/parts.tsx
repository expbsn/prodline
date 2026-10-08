import React from "react";
import { Img, staticFile } from "remotion";
import { Accent, display, theme, ui } from "./theme";

/// The Dash card (prodline/Design/ProjectCard.swift): a 5:7 playing card, the square cover on top melting into
/// the accent with a color fade and a blur, the letter badge top left, the corner stat top right, the name below.
export const ProjectCard: React.FC<{
  name: string;
  cover?: string;
  accent: Accent;
  cornerLabel: string;
  cornerValue: string;
  footnote: string;
  width?: number;
}> = ({ name, cover, accent, cornerLabel, cornerValue, footnote, width = 200 }) => {
  const s = width / 260;
  const h = (width * 7) / 5;
  const src = cover ? staticFile(cover) : undefined;
  const fade = `linear-gradient(to bottom, ${accent.base}00 42%, ${accent.base}59 68%, ${accent.base}CC 84%, ${accent.base} 96%)`;
  return (
    <div
      style={{
        width,
        height: h,
        borderRadius: 30 * s,
        overflow: "hidden",
        position: "relative",
        background: accent.base,
        boxShadow: `inset 0 0 0 1.5px rgba(255,255,255,0.7)`,
      }}
    >
      {!src && (
        // No photo: the tinted letter artwork, like a Dash card without a cover.
        <div style={{ position: "absolute", top: 0, left: 0, width, height: width, overflow: "hidden",
          background: `linear-gradient(135deg, #FFFFFF, ${accent.base}1F, ${accent.base}47)` }}>
          <div style={{ position: "absolute", right: -30 * s, top: -40 * s, fontFamily: display, fontWeight: 900,
            fontSize: 300 * s, color: `${accent.base}1F`, lineHeight: 1 }}>{name[0]}</div>
          <div style={{ position: "absolute", inset: 0, background: `linear-gradient(to bottom, ${accent.base}00 42%, ${accent.base}59 68%, ${accent.base}CC 84%, ${accent.base} 96%)` }} />
        </div>
      )}
      {src && <div style={{ position: "absolute", top: 0, left: 0, width, height: width, overflow: "hidden" }}>
        <Img src={src} style={{ width, height: width, objectFit: "cover" }} />
        <Img
          src={src}
          style={{
            position: "absolute",
            inset: 0,
            width,
            height: width,
            objectFit: "cover",
            filter: `blur(${16 * s}px)`,
            maskImage: "linear-gradient(to bottom, transparent 42%, black 100%)",
            WebkitMaskImage: "linear-gradient(to bottom, transparent 42%, black 100%)",
          }}
        />
        <div style={{ position: "absolute", inset: 0, background: fade }} />
        <div style={{ position: "absolute", left: 0, right: 0, top: 0, height: width * 0.4, background: "linear-gradient(rgba(0,0,0,0.32), transparent)" }} />
      </div>}
      {/* Badge and corner stat */}
      <div style={{ position: "absolute", left: 20 * s, top: 20 * s, right: 20 * s, display: "flex", justifyContent: "space-between" }}>
        <div
          style={{
            width: 46 * s,
            height: 46 * s,
            borderRadius: 13 * s,
            background: accent.base,
            boxShadow: `inset 0 0 0 ${1.5 * s}px rgba(255,255,255,0.35), 0 ${2 * s}px ${4 * s}px ${accent.dark}59`,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontFamily: display,
            fontWeight: 800,
            fontSize: 24 * s,
            color: accent.on,
          }}
        >
          {name[0]}
        </div>
        <div style={{ textAlign: "right", color: "white", textShadow: "0 0.5px 1.5px rgba(0,0,0,0.45), 0 0 12px rgba(0,0,0,0.35)" }}>
          <div style={{ fontFamily: ui, fontWeight: 600, fontSize: 11 * s, letterSpacing: 2.2 * s, textTransform: "uppercase", opacity: 0.85 }}>
            {cornerLabel}
          </div>
          <div style={{ fontFamily: display, fontWeight: 700, fontSize: 38 * s, lineHeight: 1 }}>{cornerValue}</div>
        </div>
      </div>
      {/* Name on the slab */}
      <div style={{ position: "absolute", left: 22 * s, right: 22 * s, bottom: 22 * s, color: accent.on }}>
        <div style={{ fontFamily: ui, fontWeight: 600, fontSize: 11 * s, letterSpacing: 1.8 * s, textTransform: "uppercase", opacity: 0.8, marginBottom: 4 * s }}>
          {footnote}
        </div>
        <div style={{ fontFamily: display, fontWeight: 800, fontSize: 46 * s, lineHeight: 0.95 }}>{name}</div>
      </div>
    </div>
  );
};

/// Text cut out of a solid block: the face in the accent, the depth in its darker shade (ExtrudedText in the app).
export const Extruded: React.FC<{ text: string; size: number; accent: Accent; weight?: number }> = ({ text, size, accent, weight = 850 }) => {
  const depth = Math.max(4, Math.round(size / 14));
  const shadows = Array.from({ length: depth }, (_, i) => `${(i + 1) * 0.45}px ${(i + 1) * 0.9}px 0 ${accent.dark}`).join(", ");
  return (
    <div style={{ fontFamily: display, fontWeight: weight, fontSize: size, lineHeight: 1, color: accent.base, textShadow: shadows, whiteSpace: "nowrap" }}>
      {text}
    </div>
  );
};

/// The chunky button (ChunkyButtonStyle): a solid face on a darker edge that sinks in when pressed.
export const ChunkyButton: React.FC<{ title: string; accent: Accent; pressed?: number; width?: number }> = ({ title, accent, pressed = 0, width = 354 }) => {
  const edge = 5 * (1 - pressed);
  return (
    <div style={{ width, height: 58 + 5, position: "relative" }}>
      <div style={{ position: "absolute", left: 0, right: 0, top: 5, height: 58, borderRadius: 18, background: accent.dark }} />
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 5 - edge,
          height: 58,
          borderRadius: 18,
          background: accent.base,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontFamily: display,
          fontWeight: 700,
          fontSize: 18,
          letterSpacing: 2.4,
          textTransform: "uppercase",
          color: accent.on,
        }}
      >
        {title}
      </div>
    </div>
  );
};

/// A goal row with the app's rounded checkbox.
export const GoalRow: React.FC<{ title: string; done: number; accent: Accent }> = ({ title, done, accent }) => (
  <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
    <div
      style={{
        width: 20,
        height: 20,
        borderRadius: 6,
        boxSizing: "border-box",
        border: `2px solid ${done > 0.5 ? accent.base : theme.tertiary}`,
        background: done > 0.01 ? accent.base : "transparent",
        transform: `scale(${1 + Math.sin(Math.min(done, 1) * Math.PI) * 0.25})`,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <svg width="12" height="12" viewBox="0 0 12 12" style={{ opacity: done }}>
        <path d="M2.5 6.3 L5 8.6 L9.6 3.6" fill="none" stroke="white" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    </div>
    <div
      style={{
        fontFamily: ui,
        fontWeight: 500,
        fontSize: 15,
        color: done > 0.5 ? theme.secondary : theme.ink,
        textDecoration: done > 0.5 ? "line-through" : "none",
        textDecorationColor: theme.secondary,
      }}
    >
      {title}
    </div>
  </div>
);

/// Our cartoon flame (prodline/Design/FlameShape.swift), ported: the outline moves with time so it burns,
/// and `grow` takes it from a small teardrop to the full flame.
export function flamePath(time: number, life: number, grow: number, w: number, h: number): string {
  const sx = w / 100;
  const sy = h / 130;
  const t = time;
  const a = life;
  const g = Math.max(0.05, grow);
  const wv = (f1: number, f2: number, ph: number) => (Math.sin(t * f1 + ph) * 0.65 + Math.sin(t * f2 + ph * 1.7) * 0.35) * a;
  const rise = (y: number, lead = 0.6) => {
    const k = Math.pow(Math.min(g, 1), lead) * (g > 1 ? g : 1);
    return 130 - (130 - y) * k;
  };
  const spread = (x: number) => 50 + (x - 50) * (0.25 + 0.75 * Math.min(g, 1));
  const P = (x: number, y: number, lead = 0.6) => `${(spread(x) * sx).toFixed(2)} ${(rise(y, lead) * sy).toFixed(2)}`;

  const tip = { x: 58 + 6 * wv(4.1, 7.3, 0), y: 2 + 5 * Math.abs(wv(5.2, 9.1, 1)) };
  const left = { x: 16 + 4 * wv(5.6, 8.7, 2), y: 38 + 7 * wv(6.3, 10.1, 3) };
  const right = { x: 88 + 4 * wv(6.1, 9.4, 4), y: 30 + 7 * wv(5.8, 11.2, 5) };
  const notchL = { x: 32 + 2 * wv(4.4, 7.7, 6), y: 58 + 3 * wv(5.1, 8.2, 7) };
  const notchR = { x: 74 + 2 * wv(4.8, 8.4, 8), y: 46 + 3 * wv(5.5, 9.3, 9) };
  const breath = 1.5 * wv(3.2, 5.1, 10);

  const out = Math.min(1, Math.max(0, (g - 0.4) / 0.5));
  type Pt = { x: number; y: number };
  const bez = (p0: Pt, p1: Pt, p2: Pt, p3: Pt, u: number): Pt => {
    const v = 1 - u;
    return {
      x: v * v * v * p0.x + 3 * v * v * u * p1.x + 3 * v * u * u * p2.x + u * u * u * p3.x,
      y: v * v * v * p0.y + 3 * v * v * u * p1.y + 3 * v * u * u * p2.y + u * u * u * p3.y,
    };
  };
  const leftEdge = (u: number) => bez({ x: 6, y: 90 }, { x: 6, y: 52 }, { x: 36, y: 20 }, tip, u);
  const rightEdge = (u: number) => bez(tip, { x: 78, y: 20 }, { x: 96, y: 52 }, { x: 96, y: 88 }, u);
  const mix = (hidden: Pt, shown: Pt): Pt => ({ x: hidden.x + (shown.x - hidden.x) * out, y: hidden.y + (shown.y - hidden.y) * out });
  const lt = mix(leftEdge(0.3), left);
  const nl = mix(leftEdge(0.55), notchL);
  const nr = mix(rightEdge(0.35), notchR);
  const rt = mix(rightEdge(0.6), right);
  const c1 = mix(leftEdge(0.12), { x: 8 - breath, y: 70 });
  const c2 = mix(leftEdge(0.22), { x: lt.x - 6, y: lt.y + 18 });
  const c3 = mix(leftEdge(0.4), { x: lt.x + 6, y: lt.y + 10 });
  const c4 = mix(leftEdge(0.48), { x: nl.x - 6, y: nl.y - 4 });
  const c5 = mix(leftEdge(0.72), { x: nl.x + 2, y: 34 });
  const c6 = mix(leftEdge(0.88), { x: tip.x - 14, y: tip.y + 20 });
  const c7 = mix(rightEdge(0.12), { x: tip.x + 10, y: tip.y + 18 });
  const c8 = mix(rightEdge(0.26), { x: nr.x - 2, y: nr.y - 14 });
  const c9 = mix(rightEdge(0.45), { x: nr.x + 4, y: nr.y - 6 });
  const c10 = mix(rightEdge(0.52), { x: rt.x - 6, y: rt.y + 8 });
  const c11 = mix(rightEdge(0.75), { x: rt.x + 6, y: rt.y + 16 });
  const c12 = mix(rightEdge(0.9), { x: 98 + breath, y: 66 });
  const tipLead = 0.6 - 0.05 * out;
  const tongueLead = 0.6 + 0.4 * out;

  return [
    `M ${P(50, 130)}`,
    `C ${P(16, 130)} ${P(4 - breath, 112)} ${P(6 - breath, 90)}`,
    `C ${P(c1.x, c1.y)} ${P(c2.x, c2.y, tongueLead)} ${P(lt.x, lt.y, tongueLead)}`,
    `C ${P(c3.x, c3.y, tongueLead)} ${P(c4.x, c4.y)} ${P(nl.x, nl.y)}`,
    `C ${P(c5.x, c5.y, tipLead)} ${P(c6.x, c6.y, tipLead)} ${P(tip.x, tip.y, tipLead)}`,
    `C ${P(c7.x, c7.y, tipLead)} ${P(c8.x, c8.y)} ${P(nr.x, nr.y)}`,
    `C ${P(c9.x, c9.y)} ${P(c10.x, c10.y, tongueLead)} ${P(rt.x, rt.y, tongueLead)}`,
    `C ${P(c11.x, c11.y, tongueLead)} ${P(c12.x, c12.y)} ${P(96 + breath, 88)}`,
    `C ${P(94 + breath, 116)} ${P(78, 130)} ${P(50, 130)}`,
    "Z",
  ].join(" ");
}

/// The layered streak flame: dark extruded body, four nested layers, glow once lit.
export const Flame: React.FC<{ time: number; grow: number; bright: number; width?: number }> = ({ time, grow, bright, width = 120 }) => {
  const w = width;
  const h = w * 1.3;
  const life = 1;
  const layers = [
    { scale: 1, phase: 0, speed: 1, from: "#FF8A00", to: "#FF4B1F" },
    { scale: 0.74, phase: 1.3, speed: 1.15, from: "#FFB000", to: "#FF8A00" },
    { scale: 0.5, phase: 2.6, speed: 1.3, from: "#FFE04A", to: "#FFB000" },
    { scale: 0.27, phase: 3.9, speed: 1.5, from: "#FFFFFF", to: "#FFF0A0" },
  ];
  const glow = bright > 0 ? `drop-shadow(0 0 ${12}px rgba(255,150,0,${0.9 * bright})) drop-shadow(0 0 ${30}px rgba(255,150,0,${0.55 * bright}))` : "none";
  return (
    <div style={{ width: w, height: h, position: "relative", filter: `${glow} saturate(${0.55 + 0.45 * bright}) brightness(${1 - 0.28 * (1 - bright)})` }}>
      <svg width={w + 12} height={h + 12} style={{ position: "absolute", left: 0, top: 0, overflow: "visible" }}>
        <defs>
          {layers.map((l, i) => (
            <linearGradient key={i} id={`fl${i}`} x1="0" y1="1" x2="0" y2="0">
              <stop offset="0" stopColor={l.from} />
              <stop offset="1" stopColor={l.to} />
            </linearGradient>
          ))}
        </defs>
        {Array.from({ length: 8 }, (_, k) => 8 - k).map((i) => (
          <path key={`d${i}`} d={flamePath(time, life, grow, w, h)} fill="#8A2410" transform={`translate(${i * 0.5}, ${i * 0.9})`} />
        ))}
        {layers.map((l, i) => {
          const lw = w * l.scale;
          const lh = h * l.scale;
          return (
            <path
              key={i}
              d={flamePath(time * l.speed + l.phase, life * (1 + i * 0.25), grow, lw, lh)}
              fill={`url(#fl${i})`}
              transform={`translate(${(w - lw) / 2}, ${h - lh - i * 5 * Math.min(1, grow)})`}
            />
          );
        })}
      </svg>
    </div>
  );
};

/// The "New project" card at the end of the Dash carousel (CreateProjectCardFace).
export const CreateCard: React.FC<{ width?: number }> = ({ width = 200 }) => {
  const s = width / 260;
  const h = (width * 7) / 5;
  return (
    <div style={{ width, height: h, borderRadius: 30 * s, background: "white", position: "relative", overflow: "hidden" }}>
      <div style={{ position: "absolute", inset: 8 * s, borderRadius: 24 * s, border: `${2}px dashed ${theme.tertiary}` }} />
      <div style={{ position: "absolute", left: 24 * s, top: 24 * s, width: 64 * s, height: 64 * s, borderRadius: "50%", background: theme.ink,
        display: "flex", alignItems: "center", justifyContent: "center", color: "white", fontSize: 40 * s, fontWeight: 700, fontFamily: ui }}>+</div>
      <div style={{ position: "absolute", left: 24 * s, bottom: 24 * s, right: 24 * s }}>
        <div style={{ fontFamily: display, fontWeight: 800, fontSize: 48 * s, lineHeight: 0.95, color: theme.ink }}>New<br />project</div>
        <div style={{ fontFamily: ui, fontWeight: 500, fontSize: 14 * s, color: theme.secondary, marginTop: 10 * s }}>Pick a cover, set the clock.</div>
      </div>
    </div>
  );
};
