// Prodline landing page: one WebGL canvas behind fixed copy layers. Scroll drives five scenes
// (drawer, plan path, streak, data, ship). Each scene enters from the side through a blur, like the
// app's onboarding, and moves with springs so fast scrolling overshoots and settles like real objects.

import * as THREE from "three";
import { RoundedBoxGeometry } from "three/addons/geometries/RoundedBoxGeometry.js";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";

const RELAY = "https://prodline-relay.prodline-relay.workers.dev";
const REDUCED = matchMedia("(prefers-reduced-motion: reduce)").matches;
// ?still: no scroll smoothing (for checking a scroll position quickly).
const STILL = new URLSearchParams(location.search).has("still");
const FLOOR = -1.8;

// MARK: - Small math

const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lerp = (a, b, t) => a + (b - a) * t;
const ss = (a, b, x) => { const t = clamp((x - a) / (b - a)); return t * t * (3 - 2 * t); };
const damp = (a, b, k, dt) => lerp(a, b, 1 - Math.exp(-k * dt));
const rand = (a, b) => a + Math.random() * (b - a);

/// Damped spring; overshoots when its target jumps, which is what makes things feel heavy.
class Spring {
  constructor(x = 0, k = 140, c = 16) { this.x = x; this.v = 0; this.target = x; this.k = k; this.c = c; }
  step(dt) {
    const h = dt / 2;
    for (let i = 0; i < 2; i++) {
      this.v += (-this.k * (this.x - this.target) - this.c * this.v) * h;
      this.x += this.v * h;
    }
    return this.x;
  }
}

// MARK: - Renderer, light, camera

const canvas = document.getElementById("gl");
const mobile = matchMedia("(pointer: coarse)").matches;
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: "high-performance" });
renderer.setPixelRatio(Math.min(devicePixelRatio, mobile ? 1.75 : 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.NeutralToneMapping;
renderer.toneMappingExposure = 0.95;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;

const scene = new THREE.Scene();
scene.fog = new THREE.Fog(0xF2F2F5, 15, 36);
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
scene.environmentIntensity = 0.55;

const camera = new THREE.PerspectiveCamera(34, 1, 0.1, 80);
const CAM = new THREE.Vector3(0, 3.0, 13.5);
const LOOK = new THREE.Vector3(0, 0.1, 0);

scene.add(new THREE.HemisphereLight(0xffffff, 0xd8d8e0, 0.8));
const sun = new THREE.DirectionalLight(0xffffff, 1.9);
sun.position.set(-6, 11, 8);
sun.castShadow = true;
sun.shadow.mapSize.set(mobile ? 1024 : 2048, mobile ? 1024 : 2048);
Object.assign(sun.shadow.camera, { left: -12, right: 12, top: 12, bottom: -12, near: 1, far: 40 });
sun.shadow.bias = -0.0004;
sun.shadow.normalBias = 0.03;
sun.shadow.radius = 5;
scene.add(sun);
// A soft light that follows the pointer, so highlights slide across the clearcoat.
const glint = new THREE.PointLight(0xffffff, 10, 30, 2);
scene.add(glint);

// MARK: - Materials and shapes

function hexColor(hex) { return new THREE.Color(hex); }
/// The darker edge under a chunky surface (Accent.dark: same hue, ~78% brightness).
function edgeOf(hex) {
  const c = hexColor(hex), hsl = {};
  c.getHSL(hsl);
  return new THREE.Color().setHSL(hsl.h, Math.min(1, hsl.s * 1.05), hsl.l * 0.74);
}
const plastic = (color, o = {}) => new THREE.MeshPhysicalMaterial({
  color, roughness: 0.42, metalness: 0, clearcoat: 0.55, clearcoatRoughness: 0.32, ...o,
});
const shadowFloor = (parent) => {
  const m = new THREE.Mesh(new THREE.PlaneGeometry(80, 80), new THREE.ShadowMaterial({ opacity: 0.11 }));
  m.rotation.x = -Math.PI / 2;
  m.position.y = FLOOR;
  m.receiveShadow = true;
  parent.add(m);
  return m;
};
function cast(o) { o.traverse((m) => { if (m.isMesh) { m.castShadow = true; m.receiveShadow = true; } }); return o; }

/// A rounded puck (lathe), for path nodes and the ship button. Bottom at y = 0.
function puckGeometry(r, h, rr = 0.16) {
  const pts = [new THREE.Vector2(0, 0)];
  for (let i = 0; i <= 6; i++) { const a = -Math.PI / 2 + (i / 6) * Math.PI / 2; pts.push(new THREE.Vector2(r - rr + Math.cos(a) * rr, rr + Math.sin(a) * rr)); }
  for (let i = 0; i <= 6; i++) { const a = (i / 6) * Math.PI / 2; pts.push(new THREE.Vector2(r - rr + Math.cos(a) * rr, h - rr + Math.sin(a) * rr)); }
  pts.push(new THREE.Vector2(0, h));
  return new THREE.LatheGeometry(pts, 64);
}

/// Duolingo-style chunky solid: a colored cap riding on its darker edge. `press` 0…1 pushes the cap down.
function chunkyPuck(r, h, hex, depth = 0.22) {
  const g = new THREE.Group();
  const base = new THREE.Mesh(puckGeometry(r, h), plastic(edgeOf(hex)));
  const cap = new THREE.Mesh(puckGeometry(r, h), plastic(hexColor(hex)));
  cap.position.y = depth;
  g.add(base, cap);
  g.userData = { base, cap, depth, h };
  return cast(g);
}
function chunkyBox(w, h, d, hex, depth = 0.16, r = 0.16) {
  const g = new THREE.Group();
  const geo = new RoundedBoxGeometry(w, h, d, 5, r);
  const base = new THREE.Mesh(geo, plastic(edgeOf(hex)));
  const cap = new THREE.Mesh(geo, plastic(hexColor(hex)));
  base.position.y = h / 2;
  cap.position.y = h / 2 + depth;
  g.add(base, cap);
  g.userData = { base, cap, depth, h };
  return cast(g);
}
function setChunkyColor(g, hex) { g.userData.cap.material.color.set(hex); g.userData.base.material.color.copy(edgeOf(hex)); }

/// Canvas texture with the page fonts.
function canvasTexture(w, h, draw) {
  const c = document.createElement("canvas");
  c.width = w; c.height = h;
  const ctx = c.getContext("2d");
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = renderer.capabilities.getMaxAnisotropy();
  tex.redraw = (...args) => { ctx.clearRect(0, 0, w, h); draw(ctx, w, h, ...args); tex.needsUpdate = true; };
  tex.redraw();
  return tex;
}
const DISPLAY = "Afacad";
const UI = "-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, Helvetica, Arial, sans-serif";
const css = (hex) => "#" + hex.toString(16).padStart(6, "0");
function gray(hex) {
  const r = (hex >> 16) & 255, g = (hex >> 8) & 255, b = hex & 255;
  const l = Math.round(0.3 * r + 0.59 * g + 0.11 * b * 1.0);
  const v = Math.round(lerp(l, 200, 0.45));
  return (v << 16) | (v << 8) | v;
}

/// Dots: the page's outline motif. One instanced mesh of little spheres along a list of points.
const DOT = new THREE.SphereGeometry(1, 12, 8);
function dots(points, size, color, { opacity = 1, shadow = false } = {}) {
  const m = new THREE.InstancedMesh(DOT, new THREE.MeshStandardMaterial({ color, roughness: 0.6, transparent: opacity < 1, opacity }), points.length);
  const o = new THREE.Object3D();
  points.forEach((p, i) => { o.position.copy(p); o.scale.setScalar(size); o.updateMatrix(); m.setMatrixAt(i, o.matrix); });
  m.castShadow = shadow;
  m.userData.points = points;
  return m;
}
function sampleCurve(curve, spacing) {
  const n = Math.max(2, Math.round(curve.getLength() / spacing));
  return curve.getSpacedPoints(n);
}
/// Dotted outline of a rounded rectangle lying on the floor (x/z), centered at the origin.
function ghostRect(w, d, r, spacing = 0.2) {
  const s = new THREE.Shape();
  const x = -w / 2, y = -d / 2;
  s.moveTo(x + r, y); s.lineTo(x + w - r, y); s.quadraticCurveTo(x + w, y, x + w, y + r);
  s.lineTo(x + w, y + d - r); s.quadraticCurveTo(x + w, y + d, x + w - r, y + d);
  s.lineTo(x + r, y + d); s.quadraticCurveTo(x, y + d, x, y + d - r);
  s.lineTo(x, y + r); s.quadraticCurveTo(x, y, x + r, y);
  const n = Math.round(s.getLength() / spacing);
  return s.getSpacedPoints(n).slice(0, -1).map((p) => new THREE.Vector3(p.x, 0, p.y));
}
function ghostRing(r, spacing = 0.2) {
  const n = Math.round((Math.PI * 2 * r) / spacing);
  return Array.from({ length: n }, (_, i) => { const a = (i / n) * Math.PI * 2; return new THREE.Vector3(Math.cos(a) * r, 0, Math.sin(a) * r); });
}

// MARK: - Particles (bursts, sparks, confetti)

class Particles {
  constructor(parent, geo, max, { gravity = -16, floor = FLOOR, bounce = 0.35, shadow = true } = {}) {
    this.mesh = new THREE.InstancedMesh(geo, plastic(0xffffff, { clearcoat: 0.3 }), max);
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.mesh.castShadow = shadow;
    this.mesh.frustumCulled = false;
    this.mesh.count = 0;
    parent.add(this.mesh);
    this.max = max; this.gravity = gravity; this.floor = floor; this.bounce = bounce;
    this.ps = [];
    this.o = new THREE.Object3D();
    this.c = new THREE.Color();
  }
  spawn(origin, n, { colors, speed = 6, up = 6, spread = 1, size = 1, life = 2.4, dir = null, drag = 0.4 }) {
    for (let i = 0; i < n; i++) {
      if (this.ps.length >= this.max) this.ps.shift();
      const v = dir ? dir.clone().multiplyScalar(rand(0.7, 1.2)).add(new THREE.Vector3(rand(-1, 1), rand(-1, 1), rand(-1, 1)).multiplyScalar(spread))
        : new THREE.Vector3(rand(-1, 1) * speed * spread, rand(0.4, 1) * up, rand(-1, 1) * speed * spread);
      this.ps.push({
        p: origin.clone(), v, r: new THREE.Euler(rand(0, 6), rand(0, 6), rand(0, 6)),
        w: new THREE.Vector3(rand(-9, 9), rand(-9, 9), rand(-9, 9)), age: 0, life: life * rand(0.75, 1.2),
        s: size * rand(0.7, 1.15), color: colors[(Math.random() * colors.length) | 0], drag,
      });
    }
  }
  step(dt) {
    const { o, c } = this;
    this.ps = this.ps.filter((q) => (q.age += dt) < q.life);
    this.ps.forEach((q, i) => {
      q.v.y += this.gravity * dt;
      q.v.multiplyScalar(Math.exp(-q.drag * dt));
      q.p.addScaledVector(q.v, dt);
      if (q.p.y < this.floor + 0.04 * q.s) {
        q.p.y = this.floor + 0.04 * q.s;
        q.v.y = Math.abs(q.v.y) * this.bounce;
        q.v.x *= 0.7; q.v.z *= 0.7; q.w.multiplyScalar(0.6);
      }
      q.r.x += q.w.x * dt; q.r.y += q.w.y * dt; q.r.z += q.w.z * dt;
      const fade = 1 - ss(q.life * 0.7, q.life, q.age);
      o.position.copy(q.p); o.rotation.copy(q.r); o.scale.setScalar(q.s * fade * ss(0, 0.08, q.age));
      o.updateMatrix();
      this.mesh.setMatrixAt(i, o.matrix);
      this.mesh.setColorAt(i, c.set(q.color));
    });
    this.mesh.count = this.ps.length;
    this.mesh.instanceMatrix.needsUpdate = true;
    if (this.mesh.instanceColor) this.mesh.instanceColor.needsUpdate = true;
  }
}
const CONFETTI = new RoundedBoxGeometry(0.2, 0.06, 0.13, 2, 0.02);
const CHIP = new RoundedBoxGeometry(0.11, 0.11, 0.11, 2, 0.03);
const SWATCHES = [0x58CC02, 0x00B894, 0x1CB0F6, 0x5B5BF0, 0xA35CFF, 0xFF5FA2, 0xFF4B4B, 0xFF9600, 0xFFC800];

// MARK: - Scene 0: the drawer

const PROJECTS = [
  { name: "Habit Hero", hex: 0x58CC02, line: "Checkpoint 2 · Streak screen", prog: 0.66 },
  { name: "Pixel Pals", hex: 0xA35CFF, line: "Checkpoint 4 · Beta", prog: 0.4 },
  { name: "Tiny Invoice", hex: 0x1CB0F6, line: "Checkpoint 1 · Core loop", prog: 0.25 },
  { name: "Recipe Box", hex: 0xFF9600, line: "Checkpoint 3 · Paywall", prog: 0.8 },
  { name: "Moodboard", hex: 0xFF5FA2, line: "Checkpoint 2 · Onboarding", prog: 0.5 },
];
const CARD_W = 2.3, CARD_H = 1.5, CARD_D = 0.12;

function drawProjectCard(ctx, w, h, p, dull) {
  const hex = dull ? gray(p.hex) : p.hex;
  const r = 46;
  ctx.fillStyle = dull ? "#ECECEF" : "#FFFFFF";
  ctx.beginPath(); ctx.roundRect(0, 0, w, h, r); ctx.fill();
  // cover band
  ctx.save(); ctx.beginPath(); ctx.roundRect(0, 0, w, h, r); ctx.clip();
  ctx.fillStyle = css(hex); ctx.fillRect(0, 0, w, h * 0.36);
  ctx.globalAlpha = 0.16; ctx.fillStyle = "#fff";
  for (let i = 0; i < 9; i++) { ctx.beginPath(); ctx.arc(w * 0.62 + i * 46, h * 0.18 - (i % 2) * 30, 12, 0, Math.PI * 2); ctx.fill(); }
  ctx.restore();
  // badge
  const bx = 40, by = h * 0.36 - 58, bs = 116;
  ctx.fillStyle = css(edgeOf(hex).getHex()); ctx.beginPath(); ctx.roundRect(bx, by + 9, bs, bs, 34); ctx.fill();
  ctx.fillStyle = css(hex); ctx.beginPath(); ctx.roundRect(bx, by, bs, bs, 34); ctx.fill();
  ctx.strokeStyle = "#fff"; ctx.lineWidth = 8; ctx.stroke();
  ctx.fillStyle = "#fff"; ctx.font = `800 70px ${DISPLAY}`; ctx.textAlign = "center"; ctx.textBaseline = "middle";
  ctx.fillText(p.name[0], bx + bs / 2, by + bs / 2 + 4);
  ctx.textAlign = "left"; ctx.textBaseline = "alphabetic";
  ctx.fillStyle = dull ? "#9A9AA0" : "#1C1C1E"; ctx.font = `800 64px ${DISPLAY}`;
  ctx.fillText(p.name, 40, h * 0.36 + 120);
  ctx.fillStyle = "#8E8E93"; ctx.font = `600 28px ${UI}`;
  ctx.fillText(dull ? "Last touched 214 days ago" : p.line, 40, h * 0.36 + 168);
  // progress
  const py = h - 64, pw = w - 80;
  ctx.fillStyle = "#E5E5EA"; ctx.beginPath(); ctx.roundRect(40, py, pw, 20, 10); ctx.fill();
  ctx.fillStyle = css(hex); ctx.beginPath(); ctx.roundRect(40, py, Math.max(20, pw * (dull ? 0.08 : p.prog)), 20, 10); ctx.fill();
}

function makeCard(p) {
  const g = new THREE.Group();
  const body = new THREE.Mesh(new RoundedBoxGeometry(CARD_W, CARD_H, CARD_D, 4, 0.06), plastic(0xffffff, { roughness: 0.5 }));
  g.add(body);
  const face = (dull) => {
    const tex = canvasTexture(768, 500, (ctx, w, h) => drawProjectCard(ctx, w, h, p, dull));
    const m = new THREE.Mesh(new THREE.PlaneGeometry(CARD_W - 0.02, CARD_H - 0.02),
      new THREE.MeshPhysicalMaterial({ map: tex, transparent: true, roughness: 0.45, clearcoat: 0.6, clearcoatRoughness: 0.2, depthWrite: !!dull }));
    m.position.z = CARD_D / 2 + (dull ? 0.002 : 0.004);
    g.add(m);
    return m;
  };
  g.userData.dull = face(true);
  g.userData.live = face(false);
  return cast(g);
}

function buildDrawer() {
  const root = new THREE.Group();
  shadowFloor(root);
  const W = 6.4, H = 2.5, D = 4.4, cy = FLOOR + H / 2, front = 1.2;
  const cabinet = new THREE.Mesh(new RoundedBoxGeometry(W, H, D, 6, 0.22), plastic(0xFBFBFD, { roughness: 0.55, clearcoat: 0.3 }));
  cabinet.position.set(0, cy, front - D / 2);
  // feet
  for (const sx of [-1, 1]) {
    const f = new THREE.Mesh(new RoundedBoxGeometry(0.5, 0.18, 0.5, 3, 0.08), plastic(0x3A3A3C));
    f.position.set(sx * (W / 2 - 0.5), FLOOR + 0.09, front - 0.5);
    cabinet.add(f); f.position.sub(cabinet.position);
  }
  root.add(cast(cabinet));

  // The drawer slides on z. Its front sits flush with the cabinet when closed.
  const drawer = new THREE.Group();
  const dw = 5.7, dh = 1.95, depth = 3.7, wall = 0.1, inner = 0xDCDCE2;
  const frontPanel = new THREE.Mesh(new RoundedBoxGeometry(dw, dh, 0.28, 5, 0.14), plastic(0xFFFFFF, { roughness: 0.38 }));
  frontPanel.position.set(0, cy, front + 0.14);
  const handle = new THREE.Mesh(new RoundedBoxGeometry(1.7, 0.26, 0.26, 4, 0.12), plastic(0x1C1C1E, { roughness: 0.3, clearcoat: 0.8 }));
  handle.position.set(0, cy + 0.15, front + 0.38);
  const label = new THREE.Mesh(new THREE.PlaneGeometry(1.25, 0.4), new THREE.MeshStandardMaterial({
    map: canvasTexture(400, 128, (ctx, w, h) => {
      ctx.fillStyle = "#F2F2F5"; ctx.beginPath(); ctx.roundRect(4, 4, w - 8, h - 8, 20); ctx.fill();
      ctx.setLineDash([3, 9]); ctx.lineCap = "round"; ctx.lineWidth = 5; ctx.strokeStyle = "#C7C7CC"; ctx.stroke();
      ctx.fillStyle = "#8E8E93"; ctx.font = `700 46px ${DISPLAY}`; ctx.textAlign = "center"; ctx.textBaseline = "middle";
      ctx.fillText("SOMEDAY", w / 2, h / 2 + 3);
    }), transparent: true, roughness: 0.6,
  }));
  label.position.set(0, cy - 0.45, front + 0.285);
  const box = new THREE.Group();
  const mat = plastic(inner, { roughness: 0.7, clearcoat: 0 });
  const part = (w, h, d, x, y, z) => { const m = new THREE.Mesh(new RoundedBoxGeometry(w, h, d, 2, 0.04), mat); m.position.set(x, y, z); box.add(m); };
  const bottomY = cy - dh / 2 + 0.12;
  part(dw - 0.3, wall, depth, 0, bottomY, front - depth / 2);
  part(wall, dh - 0.35, depth, -(dw - 0.3) / 2, bottomY + (dh - 0.35) / 2, front - depth / 2);
  part(wall, dh - 0.35, depth, (dw - 0.3) / 2, bottomY + (dh - 0.35) / 2, front - depth / 2);
  part(dw - 0.3, dh - 0.35, wall, 0, bottomY + (dh - 0.35) / 2, front - depth + wall / 2);
  drawer.add(frontPanel, handle, label, box);
  root.add(cast(drawer));

  const open = new Spring(0, 90, 11);
  const cards = PROJECTS.map((p, i) => {
    const c = makeCard(p);
    root.add(c);
    const slot = {
      x: (i - 2) * 0.32 + rand(-0.15, 0.15), y: bottomY + 0.12 + i * 0.13, z: front - depth / 2 - 0.2 + rand(-0.2, 0.2),
      rz: rand(-0.35, 0.35),
    };
    const k = Math.abs(i - 2);
    const end = new THREE.Vector3((i - 2) * 1.5 + 0.5, 2.3 - k * 0.3, 2.2 - k * 0.75);
    const endRot = new THREE.Euler(-0.1, -(i - 2) * 0.3, -(i - 2) * 0.08);
    const fly = new Spring(0, 70, 9);
    // dotted flight trail (positions recomputed when the drawer is fully out)
    const trail = dots(Array.from({ length: 26 }, () => new THREE.Vector3()), 0.035, p.hex, { opacity: 0.85 });
    trail.count = 0;
    root.add(trail);
    return { c, p, slot, end, endRot, fly, trail, spin: rand(0.8, 1.2) * (i % 2 ? 1 : -1) };
  });

  // dotted outline where the cards end up, faint until they land
  const ghosts = cards.map(({ end, endRot }) => {
    const pts = ghostRect(CARD_W, CARD_H, 0.12, 0.17).map((v) => new THREE.Vector3(v.x, -v.z, 0));
    const g = dots(pts, 0.028, 0xC7C7CC, { opacity: 0.9 });
    g.position.copy(end); g.rotation.copy(endRot);
    root.add(g);
    return g;
  });

  let rattleAt = 1.2;
  const a = new THREE.Vector3(), b = new THREE.Vector3(), q = new THREE.Vector3(), tmp = new THREE.Object3D();
  const bez = (s, m, e, t, out) => out.set(0, 0, 0).addScaledVector(s, (1 - t) ** 2).addScaledVector(m, 2 * (1 - t) * t).addScaledVector(e, t * t);

  return {
    root, extent: 5.0, lift: 0.1,
    tiltX: (p) => lerp(0.55, 0.12, ss(0.08, 0.6, p)),
    update(p, dt, t, pointer) {
      // closed: rattle now and then (something in there wants out)
      if (p < 0.03 && !REDUCED) {
        rattleAt -= dt;
        if (rattleAt < 0) { open.v += 2.6; rattleAt = rand(1.8, 3.2); }
      }
      open.target = ss(0.04, 0.26, p) * 3.3;
      const z = open.step(dt);
      drawer.position.z = Math.max(-0.02, z);

      cards.forEach((it, i) => {
        const a0 = 0.2 + i * 0.075, a1 = a0 + 0.26;
        it.fly.target = ss(a0, a1, p);
        const k = it.fly.step(dt);
        const kc = clamp(k, 0, 1.15);
        a.set(it.slot.x, it.slot.y, it.slot.z + drawer.position.z);
        b.copy(a).lerp(it.end, 0.5); b.y = Math.max(a.y, it.end.y) + 2.6; b.z += 0.9;
        if (kc <= 1) bez(a, b, it.end, kc, q); else q.copy(it.end).addScaledVector(it.end.clone().sub(b).normalize(), (kc - 1) * 1.4);
        // floating once landed
        const land = ss(0.95, 1, kc);
        const bob = REDUCED ? 0 : Math.sin(t * 1.3 + i * 1.7) * 0.08 * land;
        it.c.position.set(q.x, q.y + bob, q.z);
        const spinT = clamp(kc);
        it.c.rotation.set(
          lerp(-Math.PI / 2, it.endRot.x, ss(0, 0.7, spinT)) + pointer.y * 0.12 * land,
          lerp(0, it.endRot.y, spinT) + Math.sin(spinT * Math.PI) * 1.4 * it.spin + pointer.x * 0.22 * land,
          lerp(it.slot.rz, it.endRot.z, ss(0, 0.8, spinT)) + Math.sin(t * 0.9 + i) * 0.02 * land,
        );
        const life = ss(0.35, 0.95, kc);
        it.c.userData.live.material.opacity = life;
        it.c.userData.dull.visible = life < 0.99;
        // trail: revealed behind the card, fades once it's landed
        const n = it.trail.userData.points.length;
        const shown = Math.floor(n * clamp(kc));
        for (let j = 0; j < shown; j++) {
          bez(a, b, it.end, j / (n - 1), tmp.position); tmp.scale.setScalar(0.035); tmp.updateMatrix();
          it.trail.setMatrixAt(j, tmp.matrix);
        }
        it.trail.count = shown;
        it.trail.instanceMatrix.needsUpdate = true;
        it.trail.material.opacity = 0.85 * (1 - ss(a1 + 0.02, a1 + 0.16, p));
        it.trail.visible = it.trail.material.opacity > 0.01 && shown > 0;
        ghosts[i].material.opacity = 0.9 * ss(0.12, 0.24, p) * (1 - ss(0.9, 1, kc));
        ghosts[i].visible = ghosts[i].material.opacity > 0.01;
      });
    },
  };
}

// MARK: - Scene 1: the plan path

const CHECKPOINTS = ["Idea on paper", "Core loop", "Streak screen", "Onboarding", "Paywall", "Beta", "Ship day"];
const NODE_GAP = 3.1;

function nodeIcon(ctx, w, h, state, n) {
  ctx.clearRect(0, 0, w, h);
  ctx.strokeStyle = "#fff"; ctx.fillStyle = "#fff"; ctx.lineCap = "round"; ctx.lineJoin = "round";
  if (state === "done") {
    ctx.lineWidth = 34; ctx.beginPath(); ctx.moveTo(w * 0.3, h * 0.52); ctx.lineTo(w * 0.45, h * 0.66); ctx.lineTo(w * 0.72, h * 0.36); ctx.stroke();
  } else if (state === "ship") {
    ctx.beginPath();
    for (let i = 0; i < 10; i++) { const r = i % 2 ? w * 0.13 : w * 0.3, a = -Math.PI / 2 + i * Math.PI / 5; ctx.lineTo(w / 2 + Math.cos(a) * r, h / 2 + Math.sin(a) * r); }
    ctx.closePath(); ctx.lineWidth = 14; ctx.stroke(); ctx.fill();
  } else {
    ctx.font = `800 ${w * 0.5}px ${DISPLAY}`; ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText(String(n), w / 2, h / 2 + w * 0.03);
  }
}

function drawLabel(ctx, w, h, i) {
  ctx.fillStyle = "#fff"; ctx.beginPath(); ctx.roundRect(6, 6, w - 12, h - 12, 44); ctx.fill();
  ctx.fillStyle = "#8E8E93"; ctx.font = `600 26px ${UI}`; ctx.textBaseline = "alphabetic";
  ctx.fillText(`CHECKPOINT ${i + 1}`.split("").join(String.fromCharCode(8202)), 44, 74);
  ctx.fillStyle = "#1C1C1E"; ctx.font = `800 64px ${DISPLAY}`;
  ctx.fillText(CHECKPOINTS[i], 44, 148);
  const goals = i === 6 ? 1 : 3;
  for (let g = 0; g < goals; g++) {
    const x = 44 + g * 46;
    ctx.fillStyle = g === 0 ? "#1CB0F6" : "#E5E5EA"; ctx.beginPath(); ctx.arc(x + 14, 196, 14, 0, Math.PI * 2); ctx.fill();
  }
  ctx.fillStyle = "#8E8E93"; ctx.font = `600 26px ${UI}`;
  ctx.fillText(i === 6 ? "Press the button" : `${goals} goals`, 44 + goals * 46 + 8, 205);
}

function buildPlan() {
  const root = new THREE.Group();
  shadowFloor(root);
  const track = new THREE.Group();
  root.add(track);
  const pos = CHECKPOINTS.map((_, j) => new THREE.Vector3(Math.sin(j * 1.25 + 0.4) * 1.9, FLOOR, -j * NODE_GAP));
  // dotted path
  const curve = new THREE.CatmullRomCurve3(pos.map((p) => p.clone().setY(FLOOR + 0.07)), false, "catmullrom", 0.5);
  const pathPts = sampleCurve(curve, 0.3);
  const path = dots(pathPts, 0.07, 0xffffff, { shadow: true });
  const pathU = pathPts.map((_, i) => i / (pathPts.length - 1));
  path.setColorAt(0, new THREE.Color());
  track.add(path);

  const nodes = pos.map((p, j) => {
    const hex = j === 6 ? 0xFFC800 : 0x1CB0F6;
    const g = chunkyPuck(0.95, 0.42, hex);
    const icon = canvasTexture(256, 256, (ctx, w, h, state) => nodeIcon(ctx, w, h, state ?? (j === 6 ? "ship" : "num"), j + 1));
    const top = new THREE.Mesh(new THREE.CircleGeometry(0.78, 48), new THREE.MeshBasicMaterial({ map: icon, transparent: true, depthWrite: false }));
    top.rotation.x = -Math.PI / 2; top.position.y = 0.425;
    g.userData.cap.add(top);
    const holder = new THREE.Group();
    holder.position.copy(p);
    holder.add(g);
    const ring = dots(ghostRing(1.02, 0.2), 0.05, 0xC7C7CC, { opacity: 1 });
    ring.position.y = 0.04;
    holder.add(ring);
    // pulsing dotted halo for the current one
    const halo = dots(ghostRing(1.35, 0.24), 0.045, 0x1CB0F6, { opacity: 0.8 });
    halo.position.y = 0.05;
    holder.add(halo);
    track.add(holder);
    return { holder, g, icon, ring, halo, hex, pop: new Spring(0, 160, 12), press: new Spring(0, 260, 14), state: "", j };
  });

  const label = new THREE.Group();
  const labelTex = canvasTexture(640, 250, (ctx, w, h, i = 0) => drawLabel(ctx, w, h, i));
  const labelBody = new THREE.Mesh(new RoundedBoxGeometry(2.56, 1.0, 0.1, 4, 0.05), plastic(0xffffff));
  const labelFace = new THREE.Mesh(new THREE.PlaneGeometry(2.56, 1.0), new THREE.MeshPhysicalMaterial({ map: labelTex, transparent: true, roughness: 0.45, clearcoat: 0.5 }));
  labelFace.position.z = 0.052;
  label.add(cast(labelBody), labelFace);
  track.add(label);
  let labelIndex = 0;
  const labelSpin = new Spring(0, 90, 11);
  const labelPos = new THREE.Vector3();
  const burst = new Particles(track, CHIP, 160);
  const meta = document.getElementById("plan-meta");
  const shift = new Spring(0, 60, 12);
  const cDone = new THREE.Color(0x3A3A3C), cTodo = new THREE.Color(0xD6D6DB);
  let lastPathCur = -1;

  return {
    root, extent: 3.4, lift: 0,
    tiltX: () => 0.12,
    update(p, dt, t, pointer) {
      const cur = clamp(p * 1.12 - 0.04) * (CHECKPOINTS.length - 1);
      shift.target = cur * NODE_GAP;
      track.position.z = shift.step(dt) - 2.6;
      track.position.x = -lerp(pos[0].x, pos[6].x, 0) * 0.3 - Math.sin(cur * 1.25 + 0.4) * 1.9 * 0.7;

      nodes.forEach((n) => {
        const j = n.j;
        const appear = cur > j - 0.6;
        n.pop.target = appear ? 1 : 0;
        const s = n.pop.step(dt);
        n.g.scale.set(Math.max(0.001, s), Math.max(0.001, s * (0.6 + 0.4 * clamp(s))), Math.max(0.001, s));
        n.g.visible = s > 0.03;
        const done = cur > j + 0.4 || (j === 6 && cur > 5.9);
        const state = done ? "done" : j === 6 ? "ship" : "num";
        if (state !== n.state) {
          if (n.state && done) {
            n.press.v += 9;
            burst.spawn(n.holder.position.clone().setY(FLOOR + 0.8), 26, { colors: j === 6 ? [0xFFC800, 0xFF9600, 0xFFFFFF] : [0x58CC02, 0x89E219, 0xFFFFFF], speed: 3.2, up: 7, size: 1.1 });
          }
          n.state = state;
          n.icon.redraw(state);
          setChunkyColor(n.g, done ? (j === 6 ? 0xFFC800 : 0x58CC02) : n.hex);
        }
        const current = Math.round(cur) === j && !done;
        n.press.target = 0;
        const pr = n.press.step(dt);
        n.g.userData.cap.position.y = n.g.userData.depth * (1 - clamp(pr * 0.1, -0.4, 1));
        n.g.position.y = current && !REDUCED ? Math.abs(Math.sin(t * 3.2)) * 0.18 : 0;
        n.ring.material.opacity = 1 - clamp(s);
        n.ring.visible = n.ring.material.opacity > 0.02;
        n.halo.visible = current;
        n.halo.rotation.y = t * 0.6;
        n.halo.scale.setScalar(1 + Math.sin(t * 3.2) * 0.04);
        // sink the ones that have passed the camera
        const wz = n.holder.position.z + track.position.z;
        n.holder.position.y = FLOOR - ss(3.5, 7, wz) * 2.5;
      });

      if (Math.abs(cur - lastPathCur) > 0.01) {
        lastPathCur = cur;
        const u = cur / (CHECKPOINTS.length - 1);
        pathU.forEach((v, i) => path.setColorAt(i, v <= u ? cDone : cTodo));
        path.instanceColor.needsUpdate = true;
      }

      const idx = clamp(Math.round(cur), 0, 6);
      if (idx !== labelIndex) {
        labelSpin.target += idx > labelIndex ? Math.PI * 2 : -Math.PI * 2;
        labelIndex = idx;
        labelTex.redraw(idx);
        meta.textContent = `Checkpoint ${idx + 1} of 7 · ${CHECKPOINTS[idx]}`;
      }
      const f = cur - Math.floor(cur);
      const i0 = Math.floor(cur), i1 = Math.min(6, i0 + 1);
      labelPos.copy(pos[i0]).lerp(pos[i1], ss(0.2, 0.8, f));
      label.position.set(labelPos.x + 0.2, FLOOR + 2.3 + (REDUCED ? 0 : Math.sin(t * 1.4) * 0.08), labelPos.z + 0.3);
      label.rotation.set(-0.12 + pointer.y * 0.15, labelSpin.step(dt) + pointer.x * 0.35 - 0.15, Math.sin(t * 1.1) * 0.02);
      burst.step(dt);
    },
  };
}

// MARK: - Scene 2: streak

const DAYS = ["M", "T", "W", "T", "F", "S", "S"];

function flameGeometry(scale = 1, depth = 0.42) {
  const s = new THREE.Shape();
  s.moveTo(0, -1);
  s.bezierCurveTo(0.72, -1, 1.02, -0.5, 0.98, 0.02);
  s.bezierCurveTo(0.94, 0.62, 0.42, 0.92, 0.12, 1.55);
  s.bezierCurveTo(-0.06, 1.08, -0.32, 0.96, -0.5, 0.72);
  s.bezierCurveTo(-0.58, 0.9, -0.62, 1.0, -0.66, 1.06);
  s.bezierCurveTo(-0.98, 0.7, -1.06, 0.3, -1.0, -0.06);
  s.bezierCurveTo(-0.94, -0.62, -0.6, -1, 0, -1);
  const g = new THREE.ExtrudeGeometry(s, { depth, bevelEnabled: true, bevelThickness: 0.2, bevelSize: 0.16, bevelSegments: 6, curveSegments: 40 });
  g.center();
  g.scale(scale, scale, 1);
  return g;
}

function buildStreak() {
  const root = new THREE.Group();
  shadowFloor(root);
  const tiles = DAYS.map((d, i) => {
    const g = chunkyBox(1.02, 0.42, 1.02, 0xFF9600, 0.16, 0.18);
    const tex = canvasTexture(256, 256, (ctx, w, h) => {
      ctx.fillStyle = "#fff"; ctx.font = `800 150px ${DISPLAY}`; ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText(d, w / 2, h / 2 + 8);
    });
    const top = new THREE.Mesh(new THREE.PlaneGeometry(0.8, 0.8), new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false }));
    top.rotation.x = -Math.PI / 2; top.position.y = 0.425;
    g.userData.cap.add(top);
    const holder = new THREE.Group();
    const k = i - 3;
    holder.position.set(k * 1.32, FLOOR, 1.4 - k * k * 0.1);
    holder.rotation.y = -k * 0.07;
    holder.add(g);
    const ghost = dots(ghostRect(1.02, 1.02, 0.2, 0.17), 0.04, 0xC7C7CC);
    ghost.position.y = 0.03;
    holder.add(ghost);
    root.add(holder);
    return { holder, g, ghost, pop: new Spring(0, 170, 11), press: new Spring(0, 260, 13), on: false };
  });

  const flame = new THREE.Group();
  const outer = new THREE.Mesh(flameGeometry(1.15), plastic(0xFF9600, { emissive: 0xFF5A00, emissiveIntensity: 0.12, clearcoat: 0, roughness: 0.75, envMapIntensity: 0.15, specularIntensity: 0.3 }));
  const inner = new THREE.Mesh(flameGeometry(0.6, 0.3), plastic(0xFFC800, { emissive: 0xFFA000, emissiveIntensity: 0.25, clearcoat: 0, roughness: 0.75, envMapIntensity: 0.15, specularIntensity: 0.3 }));
  inner.position.set(-0.06, -0.42, 0.36);
  flame.add(cast(outer), cast(inner));
  flame.position.set(0, FLOOR + 1.7, -1.2);
  root.add(flame);
  const flameBase = dots(ghostRing(1.25, 0.2), 0.05, 0xC7C7CC);
  flameBase.position.set(0, FLOOR + 0.03, -1.2);
  root.add(flameBase);
  const warm = new THREE.PointLight(0xFF9A2E, 0, 9, 2);
  warm.position.set(0, FLOOR + 3.2, 1.4);
  root.add(warm);
  const grow = new Spring(0.3, 120, 10);
  const sparks = new Particles(root, CHIP, 220, { gravity: 2.5, floor: -99, shadow: false });
  const grayC = new THREE.Color(0xC7C7CC), orangeC = new THREE.Color(0xFF9600), yellowC = new THREE.Color(0xFFC800);
  const counter = document.getElementById("streak-n");
  let lastN = -1, emberT = 0;

  return {
    root, extent: 5.0, lift: 0,
    tiltX: () => 0.34,
    update(p, dt, t, pointer) {
      const n = Math.min(7, Math.floor(clamp(p * 1.18 - 0.05) * 8));
      tiles.forEach((it, i) => {
        const on = i < n;
        if (on && !it.on) {
          it.press.v += 10;
          const from = it.holder.position.clone().setY(FLOOR + 0.7);
          const to = flame.position.clone().sub(from).normalize().multiplyScalar(6).add(new THREE.Vector3(0, 3, 0));
          sparks.spawn(from, 18, { colors: [0xFF9600, 0xFFC800, 0xFFE04A], dir: to, spread: 1.4, size: 0.9, life: 1.1, drag: 1.2 });
          grow.v += 1.5;
        }
        it.on = on;
        it.pop.target = on ? 1 : 0;
        const s = it.pop.step(dt);
        it.g.scale.set(Math.max(0.001, lerp(0.6, 1, clamp(s))), Math.max(0.001, s), Math.max(0.001, lerp(0.6, 1, clamp(s))));
        it.g.visible = s > 0.03;
        const pr = it.press.step(dt);
        it.press.target = 0;
        it.g.userData.cap.position.y = it.g.userData.depth * (1 - clamp(pr * 0.1, -0.4, 1));
        it.ghost.material.opacity = 1 - clamp(s);
        it.ghost.visible = it.ghost.material.opacity > 0.02;
      });
      if (n !== lastN) { counter.textContent = String(n); lastN = n; }

      const lit = n / 7;
      grow.target = n === 0 ? 0.55 : 0.7 + lit * 0.55;
      const g = grow.step(dt);
      const flick = REDUCED ? 0 : (Math.sin(t * 9.1) * 0.035 + Math.sin(t * 14.3) * 0.02) * (n ? 1 : 0.2);
      flame.scale.set(g * (1 - flick * 0.6), g * (1 + flick), g);
      flame.rotation.set(0, pointer.x * 0.45 + Math.sin(t * 0.8) * 0.12, Math.sin(t * 2.3) * 0.04 * (n ? 1 : 0));
      outer.material.color.copy(grayC).lerp(orangeC, ss(0, 1, n));
      inner.material.color.copy(grayC).lerp(yellowC, ss(0, 1, n));
      outer.material.emissiveIntensity = n ? 0.02 + lit * 0.05 + flick * 0.5 : 0;
      inner.material.emissiveIntensity = n ? 0.05 + lit * 0.1 : 0;
      warm.intensity = n ? 2 + lit * 6 + flick * 8 : 0;
      flameBase.material.opacity = 1 - ss(0, 1, n);
      flameBase.visible = flameBase.material.opacity > 0.02;

      emberT -= dt;
      if (n > 0 && emberT < 0 && !REDUCED) {
        emberT = 0.22 - lit * 0.15;
        sparks.spawn(flame.position.clone().add(new THREE.Vector3(rand(-0.4, 0.4) * g, 0.9 * g, rand(-0.1, 0.4))), 1,
          { colors: [0xFF9600, 0xFFC800], dir: new THREE.Vector3(0, 1.4, 0), spread: 0.5, size: 0.55, life: 1.6, drag: 0.6 });
      }
      sparks.step(dt);
    },
  };
}

// MARK: - Scene 3: data flowing in

const SOURCES = [
  { name: "Stripe", what: "sales", hex: 0x5B5BF0 },
  { name: "App Store", what: "downloads", hex: 0x1CB0F6 },
  { name: "YouTube", what: "views", hex: 0xFF4B4B },
  { name: "Plausible", what: "visits", hex: 0x5B5BF0 },
  { name: "RevenueCat", what: "MRR", hex: 0xFF5FA2 },
  { name: "Vercel", what: "deploys", hex: 0x1C1C1E },
];
// A month of revenue, cumulative, a little bumpy.
const SERIES = (() => { let v = 0; return Array.from({ length: 42 }, (_, i) => (v += 12 + Math.max(0, Math.sin(i * 0.9) * 28 + Math.sin(i * 0.37) * 22 + (i > 24 ? 30 : 0)))); })();

function drawChartCard(ctx, w, h, prog, t) {
  ctx.fillStyle = "#fff"; ctx.beginPath(); ctx.roundRect(0, 0, w, h, 60); ctx.fill();
  const n = Math.max(1, Math.floor(prog * (SERIES.length - 1)));
  const last = SERIES[n], max = SERIES[SERIES.length - 1] * 1.08;
  ctx.fillStyle = "#58CC02"; ctx.beginPath(); ctx.roundRect(56, 54, 84, 84, 26); ctx.fill();
  ctx.fillStyle = "#fff"; ctx.font = `800 52px ${DISPLAY}`; ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText("H", 98, 99);
  ctx.textAlign = "left"; ctx.textBaseline = "alphabetic";
  ctx.fillStyle = "#1C1C1E"; ctx.font = `800 46px ${DISPLAY}`; ctx.fillText("Habit Hero", 162, 92);
  ctx.fillStyle = "#8E8E93"; ctx.font = `600 24px ${UI}`; ctx.fillText("REVENUE · THIS MONTH", 162, 128);
  ctx.fillStyle = "#1C1C1E"; ctx.font = `800 120px ${DISPLAY}`;
  ctx.fillText("$" + Math.round(last).toLocaleString("en-US"), 56, 270);
  const gain = Math.round(SERIES[n] - SERIES[Math.max(0, n - 7)]);
  ctx.font = `700 30px ${UI}`; ctx.fillStyle = "#46A302"; ctx.fillText(`+$${gain} this week`, 60, 318);
  // chart, straight segments
  const x0 = 56, x1 = w - 56, y0 = h - 60, y1 = 360;
  const X = (i) => x0 + (i / (SERIES.length - 1)) * (x1 - x0), Y = (v) => y0 - (v / max) * (y0 - y1);
  ctx.setLineDash([2, 12]); ctx.lineCap = "round"; ctx.strokeStyle = "#D1D1D6"; ctx.lineWidth = 4;
  for (let gy = 0; gy < 3; gy++) { const y = y1 + ((y0 - y1) * gy) / 2; ctx.beginPath(); ctx.moveTo(x0, y); ctx.lineTo(x1, y); ctx.stroke(); }
  ctx.setLineDash([]);
  const grad = ctx.createLinearGradient(0, y1, 0, y0);
  grad.addColorStop(0, "rgba(88,204,2,0.28)"); grad.addColorStop(1, "rgba(88,204,2,0)");
  ctx.beginPath(); ctx.moveTo(X(0), y0);
  for (let i = 0; i <= n; i++) ctx.lineTo(X(i), Y(SERIES[i]));
  ctx.lineTo(X(n), y0); ctx.closePath(); ctx.fillStyle = grad; ctx.fill();
  ctx.beginPath();
  for (let i = 0; i <= n; i++) i ? ctx.lineTo(X(i), Y(SERIES[i])) : ctx.moveTo(X(i), Y(SERIES[i]));
  ctx.strokeStyle = "#58CC02"; ctx.lineWidth = 8; ctx.lineJoin = "round"; ctx.stroke();
  const pulse = 1 + Math.sin(t * 5) * 0.25;
  ctx.fillStyle = "rgba(88,204,2,0.2)"; ctx.beginPath(); ctx.arc(X(n), Y(last), 26 * pulse, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = "#58CC02"; ctx.beginPath(); ctx.arc(X(n), Y(last), 13, 0, Math.PI * 2); ctx.fill();
  ctx.strokeStyle = "#fff"; ctx.lineWidth = 5; ctx.stroke();
}

function buildData() {
  const root = new THREE.Group();
  shadowFloor(root);
  const board = new THREE.Group();
  const BW = 4.3, BH = 3.1;
  const body = new THREE.Mesh(new RoundedBoxGeometry(BW, BH, 0.2, 5, 0.1), plastic(0xffffff));
  const tex = canvasTexture(1024, 740, (ctx, w, h, prog = 0, t = 0) => drawChartCard(ctx, w, h, prog, t));
  const face = new THREE.Mesh(new THREE.PlaneGeometry(BW - 0.04, BH - 0.04), new THREE.MeshPhysicalMaterial({ map: tex, transparent: true, roughness: 0.4, clearcoat: 0.7, clearcoatRoughness: 0.15 }));
  face.position.z = 0.102;
  board.add(cast(body), face);
  // little stand so it sits on the floor
  const stand = chunkyBox(1.3, 0.22, 0.9, 0xE5E5EA, 0.08, 0.1);
  stand.position.set(0, FLOOR, 0);
  root.add(stand);
  board.position.set(0, FLOOR + 0.3 + BH / 2, 0);
  root.add(board);

  const tiles = SOURCES.map((s, i) => {
    const g = new THREE.Group();
    const geo = new RoundedBoxGeometry(1.5, 0.96, 0.3, 5, 0.14);
    const base = new THREE.Mesh(geo, plastic(edgeOf(s.hex)));
    const cap = new THREE.Mesh(geo, plastic(0xffffff));
    base.position.z = -0.1;
    const t = canvasTexture(384, 246, (ctx, w, h) => {
      ctx.fillStyle = css(s.hex); ctx.beginPath(); ctx.arc(44, 52, 16, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = "#1C1C1E"; ctx.font = `800 58px ${DISPLAY}`; ctx.textBaseline = "alphabetic"; ctx.fillText(s.name, 30, 150);
      ctx.fillStyle = "#8E8E93"; ctx.font = `600 26px ${UI}`; ctx.fillText(s.what.toUpperCase(), 32, 200);
    });
    const f = new THREE.Mesh(new THREE.PlaneGeometry(1.46, 0.94), new THREE.MeshBasicMaterial({ map: t, transparent: true }));
    f.position.z = 0.152;
    cap.add(f);
    g.add(base, cap);
    cast(g);
    const a = (i / SOURCES.length) * Math.PI * 2 + 0.5;
    const home = new THREE.Vector3(Math.cos(a) * 3.3, FLOOR + 2.1 + Math.sin(a) * 1.75, -1.3 + Math.sin(a * 2) * 0.4);
    const from = home.clone().multiplyScalar(3.2).add(new THREE.Vector3(0, 4, 3));
    root.add(g);
    // stream of dots flowing from this tile into the board
    const streamN = 14;
    const stream = dots(Array.from({ length: streamN }, () => new THREE.Vector3()), 0.05, s.hex === 0x1C1C1E ? 0x3A3A3C : s.hex);
    stream.count = 0;
    root.add(stream);
    return { g, home, from, a, stream, streamN, fly: new Spring(0, 80, 10), s };
  });

  const ripple = new Particles(root, CHIP, 120, { gravity: -12 });
  const mid = new THREE.Vector3(), tmp = new THREE.Object3D(), tgt = new THREE.Vector3();
  const rev = document.getElementById("stat-rev"), vis = document.getElementById("stat-visits"), dl = document.getElementById("stat-dl");
  let lastDraw = -1, drawClock = 0;

  return {
    root, extent: 4.5, lift: 0,
    tiltX: () => 0.06,
    update(p, dt, t, pointer) {
      const prog = ss(0.12, 0.92, p);
      tiles.forEach((it, i) => {
        it.fly.target = ss(0.02 + i * 0.05, 0.22 + i * 0.05, p);
        const k = it.fly.step(dt);
        it.g.position.copy(it.from).lerp(it.home, k);
        it.g.position.y += REDUCED ? 0 : Math.sin(t * 1.2 + i * 1.3) * 0.1 * clamp(k);
        it.g.rotation.set(0.1 - pointer.y * 0.1 + (1 - clamp(k)) * 1.6, -it.home.x * 0.09 + pointer.x * 0.25 + (1 - clamp(k)) * 2.4 * (i % 2 ? 1 : -1), Math.sin(t * 0.7 + i) * 0.04);
        // flow
        const flowing = k > 0.9 && prog > 0 && prog < 0.999;
        tgt.set(board.position.x + (it.home.x > 0 ? 1 : -1) * 1.2, board.position.y + 0.2 * (it.home.y > 0 ? 1 : -1), board.position.z + 0.15);
        mid.copy(it.g.position).lerp(tgt, 0.5); mid.z += 1.6; mid.y += 0.6;
        if (flowing || it.stream.count) {
          const shown = flowing ? it.streamN : Math.max(0, it.stream.count - 1);
          for (let j = 0; j < shown; j++) {
            const u = ((t * 0.55 + j / it.streamN + i * 0.13) % 1);
            const v = 1 - u;
            tmp.position.set(0, 0, 0).addScaledVector(it.g.position, v * v).addScaledVector(mid, 2 * v * u).addScaledVector(tgt, u * u);
            tmp.scale.setScalar(0.05 * (Math.sin(u * Math.PI) * 1.2 + 0.2));
            tmp.updateMatrix();
            it.stream.setMatrixAt(j, tmp.matrix);
          }
          it.stream.count = shown;
          it.stream.instanceMatrix.needsUpdate = true;
        }
      });
      // board: angled, follows pointer, drifts as the month fills in
      board.rotation.set(-0.08 + pointer.y * 0.12, lerp(-0.5, -0.16, prog) + pointer.x * 0.3, lerp(0.04, 0, prog));
      drawClock -= dt;
      if (Math.abs(prog - lastDraw) > 0.003 || drawClock < 0) {
        tex.redraw(prog, t);
        if (Math.floor(prog * 41) > Math.floor(lastDraw * 41) && lastDraw >= 0 && !REDUCED) {
          ripple.spawn(new THREE.Vector3(1.4, FLOOR + 3.3, 0.6), 4, { colors: [0x58CC02, 0xFFC800], speed: 1.5, up: 4, size: 0.7, life: 1.2 });
        }
        lastDraw = prog; drawClock = 1 / 20;
        const n = Math.max(1, Math.floor(prog * (SERIES.length - 1)));
        rev.textContent = "$" + Math.round(SERIES[n]).toLocaleString("en-US");
        vis.textContent = Math.round(prog * 12400).toLocaleString("en-US");
        dl.textContent = Math.round(prog * 860).toLocaleString("en-US");
      }
      ripple.step(dt);
    },
  };
}

// MARK: - Scene 4: ship it

function buildShip() {
  const root = new THREE.Group();
  shadowFloor(root);
  const btn = chunkyPuck(1.7, 0.7, 0x58CC02, 0.34);
  const tex = canvasTexture(512, 512, (ctx, w, h) => {
    ctx.fillStyle = "#fff"; ctx.font = `800 132px ${DISPLAY}`; ctx.textAlign = "center"; ctx.textBaseline = "middle";
    ctx.fillText("SHIP", w / 2, h / 2 + 10);
  });
  const top = new THREE.Mesh(new THREE.CircleGeometry(1.4, 64), new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false }));
  top.rotation.x = -Math.PI / 2; top.position.y = 0.705;
  btn.userData.cap.add(top);
  // a dark plinth so the press has something to travel into
  const plinth = new THREE.Mesh(puckGeometry(2.1, 0.32, 0.14), plastic(0xFFFFFF, { roughness: 0.5 }));
  const pivot = new THREE.Group();
  pivot.add(cast(plinth));
  btn.position.y = 0.2;
  pivot.add(btn);
  pivot.position.set(0, FLOOR, 0);
  root.add(pivot);
  const ringPts = ghostRing(2.5, 0.22);
  const rings = [0, 1, 2].map(() => { const r = dots(ringPts, 0.05, 0xC7C7CC, { opacity: 0 }); r.position.set(0, FLOOR + 0.04, 0); root.add(r); return { r, age: 9 }; });
  const confetti = new Particles(root, CONFETTI, 260, { gravity: -15, bounce: 0.3 });
  const press = new Spring(0, 300, 16);
  const ray = new THREE.Raycaster();
  let hover = false, held = false, waveT = 0;

  function fire(big = false) {
    press.v += 14;
    confetti.spawn(new THREE.Vector3(0, FLOOR + 1.2, 0), big ? 180 : 90, { colors: SWATCHES, speed: 4.2, up: big ? 15 : 12, size: 1.3, life: 4.5, drag: 0.5 });
    rings.forEach((x, i) => (x.age = -i * 0.12));
  }

  return {
    root, extent: 2.9, lift: 0.1, fire,
    tiltX: () => 0.38,
    hit(ndc) {
      ray.setFromCamera(ndc, camera);
      return ray.intersectObject(btn, true).length > 0;
    },
    setHover(h) { hover = h; },
    setHeld(h) { held = h; },
    update(p, dt, t, pointer) {
      press.target = held ? 1 : hover ? 0.35 : 0;
      const pr = press.step(dt);
      btn.userData.cap.position.y = btn.userData.depth * (1 - clamp(pr, -0.3, 1));
      pivot.rotation.set(pointer.y * 0.18, pointer.x * 0.5 + Math.sin(t * 0.5) * 0.1, -pointer.x * 0.05);
      // idle invitation: a little wobble every few seconds
      waveT -= dt;
      if (waveT < 0 && !REDUCED && !hover) { press.v += 2.2; waveT = 3.2; }
      rings.forEach((x) => {
        x.age += dt;
        const a = clamp(x.age / 1.1);
        x.r.scale.setScalar(0.7 + a * 1.4);
        x.r.material.opacity = x.age < 0 ? 0 : (1 - a) * 0.9;
        x.r.visible = x.r.material.opacity > 0.01;
      });
      confetti.step(dt);
    },
  };
}

// MARK: - Layout, scroll and choreography

const beats = [...document.querySelectorAll(".beat")];
const lens = beats.map((b) => parseFloat(b.dataset.len));
let scenes = [];
let starts = [], total = 0, vh = innerHeight, vw = innerWidth;

function measure() {
  vh = innerHeight; vw = innerWidth;
  starts = []; total = 0;
  lens.forEach((l) => { starts.push(total); total += l * vh; });
  document.getElementById("space").style.height = `${total + vh}px`;
  renderer.setSize(vw, vh, false);
  camera.aspect = vw / vh;
  camera.updateProjectionMatrix();
  layoutRail();
}

const rail = document.querySelector(".rail");
function layoutRail() {
  rail.querySelectorAll("a").forEach((a) => a.remove());
  beats.forEach((b, i) => {
    const a = document.createElement("a");
    a.href = `#${b.id}`;
    a.dataset.go = String(i);
    a.setAttribute("aria-label", b.querySelector("h1, h2").textContent);
    a.style.top = `${(starts[i] / Math.max(1, total)) * 100}%`;
    rail.appendChild(a);
  });
}

function goTo(i) {
  const y = i === 0 ? 0 : i === beats.length - 1 ? total : starts[i] + vh * 0.55;
  scrollTo({ top: y, behavior: REDUCED ? "auto" : "smooth" });
}
document.addEventListener("click", (e) => {
  const a = e.target.closest("[data-go]");
  if (!a) return;
  e.preventDefault();
  goTo(Number(a.dataset.go));
});

const pointer = { x: 0, y: 0, tx: 0, ty: 0 };
const ndc = new THREE.Vector2(-9, -9);
addEventListener("pointermove", (e) => {
  pointer.tx = (e.clientX / vw) * 2 - 1;
  pointer.ty = (e.clientY / vh) * 2 - 1;
  ndc.set(pointer.tx, -pointer.ty);
}, { passive: true });

let smoothY = scrollY;

/// Where a scene sits: right of the copy on wide screens, under it on tall ones.
function placement(extent) {
  const dist = CAM.length();
  const hh = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)) * dist;
  const hw = hh * camera.aspect;
  if (camera.aspect > 1.05) {
    const avail = hw * 0.62;
    return { x: hw * 0.4, y: -hh * 0.05, s: Math.min(1.15, avail / extent) };
  }
  const avail = hw * 0.98;
  return { x: 0, y: -hh * 0.42, s: Math.min(0.9, avail / extent) };
}

function frame(dt, t) {
  smoothY = REDUCED || STILL ? scrollY : damp(smoothY, scrollY, 7, dt);
  const y = smoothY;
  pointer.x = damp(pointer.x, pointer.tx, 4, dt);
  pointer.y = damp(pointer.y, pointer.ty, 4, dt);

  let best = 0, bestI = 0;
  beats.forEach((el, i) => {
    const s0 = starts[i], L = lens[i] * vh;
    const e = i === 0 ? 1 : ss(s0 - 0.38 * vh, s0 + 0.32 * vh, y);
    const x = i === beats.length - 1 ? 0 : ss(s0 + L - 0.42 * vh, s0 + L + 0.3 * vh, y);
    const p = i === beats.length - 1 ? clamp((y - s0) / Math.max(1, total - s0)) : clamp((y - s0) / L);
    const vis = e * (1 - x);
    if (vis > best) { best = vis; bestI = i; }

    // copy: each line slides in from the side through a blur, a beat after the one above it
    const kids = el.querySelectorAll("[data-k]");
    kids.forEach((k, j) => {
      const ei = clamp(e * 1.35 - j * 0.08), xi = clamp(x * 1.35 - (kids.length - 1 - j) * 0.05);
      const v = ss(0, 1, ei) * (1 - ss(0, 1, xi));
      k.style.opacity = v.toFixed(3);
      k.style.filter = v > 0.995 ? "none" : `blur(${((1 - v) * 14).toFixed(1)}px)`;
      k.style.transform = `translate3d(${((1 - ss(0, 1, ei)) * 70 - ss(0, 1, xi) * 70).toFixed(1)}px, 0, 0)`;
    });
    el.classList.toggle("live", vis > 0.6);
    el.style.visibility = vis > 0.002 ? "visible" : "hidden";

    // scene
    const sc = scenes[i];
    if (!sc) return;
    const on = vis > 0.002;
    sc.root.visible = on;
    if (!on) return;
    const pl = placement(sc.extent);
    const ein = 1 - ss(0, 1, e), xout = ss(0, 1, x);
    sc.root.position.set(pl.x + ein * 9 - xout * 9, pl.y + sc.lift - ein * 0.6 - xout * 0.6, -ein * 3 - xout * 3);
    sc.root.rotation.set(sc.tiltX(p), -ein * 0.9 + xout * 0.9, ein * 0.08 - xout * 0.08);
    sc.root.scale.setScalar(pl.s);
    sc.update(p, dt, t, pointer);
  });
  document.body.style.setProperty("--scene-blur", `${((1 - best) * 16).toFixed(1)}px`);
  document.querySelectorAll(".tab").forEach((a) => a.classList.toggle("on", Number(a.dataset.go) === bestI));
  document.querySelector(".plus").classList.toggle("on", bestI === beats.length - 1);
  rail.querySelectorAll("a").forEach((a, i) => { a.classList.toggle("on", i === bestI); a.classList.toggle("past", i < bestI); });
  rail.style.setProperty("--rail", clamp(y / Math.max(1, total)).toFixed(4));

  // camera: a touch of parallax
  camera.position.set(CAM.x + pointer.x * 0.5, CAM.y - pointer.y * 0.3, CAM.z);
  camera.lookAt(LOOK);
  glint.position.set(pointer.x * 9, 4 - pointer.y * 4, 7);
  renderer.render(scene, camera);
}

// MARK: - Ship button: pointer + form

function hookShip(ship) {
  const interactive = (el) => el.closest("a, button, input, label, form");
  let down = false;
  addEventListener("pointermove", (e) => {
    if (!ship.root.visible) return;
    const h = !interactive(e.target) && ship.hit(ndc);
    ship.setHover(h);
    document.body.style.cursor = h ? "pointer" : "";
  }, { passive: true });
  addEventListener("pointerdown", (e) => {
    pointer.tx = (e.clientX / vw) * 2 - 1; pointer.ty = (e.clientY / vh) * 2 - 1; ndc.set(pointer.tx, -pointer.ty);
    if (!ship.root.visible || interactive(e.target) || !ship.hit(ndc)) return;
    down = true; ship.setHeld(true);
  });
  addEventListener("pointerup", () => {
    if (!down) return;
    down = false; ship.setHeld(false); ship.fire();
  });

  const form = document.getElementById("waitlist");
  const note = document.getElementById("form-note");
  const btn = form.querySelector("button");
  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const email = form.email.value.trim();
    form.classList.remove("bad");
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
      void form.offsetWidth; form.classList.add("bad");
      note.className = "fine err"; note.textContent = "That email looks a little off.";
      return;
    }
    btn.disabled = true; btn.textContent = "…";
    try {
      const r = await fetch(`${RELAY}/waitlist`, {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ email, website: form.website.value }),
      });
      if (!r.ok) throw new Error(String(r.status));
      const body = await r.json();
      note.className = "fine ok";
      note.textContent = body.already ? "You're already on the list. We haven't forgotten you." : "You're on the list. Keep that project warm.";
      btn.textContent = "Done";
      form.email.value = "";
      ship.fire(true);
    } catch {
      note.className = "fine err"; note.textContent = "Couldn't reach the list. Try again in a moment.";
      btn.disabled = false; btn.textContent = "Join";
    }
  });
}

// MARK: - Start

async function start() {
  try { await Promise.race([document.fonts.load(`800 40px ${DISPLAY}`), new Promise((r) => setTimeout(r, 2500))]); } catch {}
  scenes = [buildDrawer(), buildPlan(), buildStreak(), buildData(), buildShip()];
  scenes.forEach((s) => { s.root.visible = false; scene.add(s.root); });
  hookShip(scenes[4]);
  measure();
  addEventListener("resize", () => { if (innerWidth !== vw || Math.abs(innerHeight - vh) > 120) measure(); else { vh = innerHeight; renderer.setSize(vw, vh, false); camera.aspect = vw / vh; camera.updateProjectionMatrix(); } });
  smoothY = scrollY;
  renderer.compile(scene, camera);
  // ?still: settle the springs by hand (hidden tabs don't get animation frames)
  if (STILL) { window.scenes = scenes; window.camera = camera; document.body.classList.add("ready"); canvas.style.transition = "none"; canvas.style.opacity = 1; }
  if (STILL) window.settle = (n = 240) => { for (let i = 0; i < n; i++) frame(1 / 60, performance.now() / 1000 + i / 60); };
  let last = performance.now();
  const loop = (now) => {
    const dt = Math.min(1 / 30, (now - last) / 1000);
    last = now;
    frame(dt, now / 1000);
    requestAnimationFrame(loop);
  };
  requestAnimationFrame((now) => { last = now; loop(now); requestAnimationFrame(() => document.body.classList.add("ready")); });
}
start();
