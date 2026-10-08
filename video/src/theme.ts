// The app's design tokens (Shared/DesignCore.swift), in points. The video is laid out at 402 × 874 points
// and zoomed 3× so text and shapes render at full resolution.
export const W = 402;
export const H = 874;

export const theme = {
  ink: "#1C1C1E",
  inkSoft: "#3A3A3C",
  secondary: "#8E8E93",
  tertiary: "#C7C7CC",
  line: "#E5E5EA",
  background: "#F2F2F5",
  card: "#FFFFFF",
  flame: "#FF9600",
  success: "#34C759",
};

export type Accent = { base: string; dark: string; on: string };

export const accents = {
  green: { base: "#58CC02", dark: "#46A302", on: "#FFFFFF" },
  purple: { base: "#A35CFF", dark: "#7F45C9", on: "#FFFFFF" },
  charcoal: { base: "#3A3A3C", dark: "#26262A", on: "#FFFFFF" },
  gold: { base: "#FFC800", dark: "#C79C00", on: "#1C1C1E" },
  orange: { base: "#FF9600", dark: "#C76F00", on: "#FFFFFF" },
} satisfies Record<string, Accent>;

export const display = "'Afacad Flux', 'SF Pro Rounded', system-ui";
export const ui = "-apple-system, 'SF Pro Text', system-ui, sans-serif";
