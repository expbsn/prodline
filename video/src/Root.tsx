import { Composition } from "remotion";
import { Intro, INTRO_FRAMES } from "./Intro";

// Full iPhone screen including the safe areas: iPhone 17 Pro, 402 × 874 points at 3×.
export const Root = () => (
  <Composition id="Intro" component={Intro} durationInFrames={INTRO_FRAMES} fps={60} width={1206} height={2622} />
);
