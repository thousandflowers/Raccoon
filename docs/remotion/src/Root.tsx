import React from 'react';
import {Composition} from 'remotion';
import {Terminal, TerminalProps} from './Terminal';
import data from './data.json';

const FPS = 30;
const TYPE = 2, PAD = 6, REVEAL = 4, HOLD = 40;

// Terminal.tsx draws HEADER_H of chrome above the output and LH per line.
// A composition grows to fit its fixture so that a fixture which fits is not
// scrolled off its own first line: the menu is 32 lines and used to end on
// the last category with the raccoon already gone. Past the cap, long reports
// scroll as before - env is 88 lines and is meant to.
const HEADER_H = 96, LH = 30, CHROME = 96, MAX_H = 1250, MIN_H = 620;
const heightFor = (lines: number) => {
  const needed = HEADER_H + CHROME + lines * LH;
  // Grow only when growing buys something. A fixture past the cap scrolls at
  // any height, so paying for the extra pixels just makes the GIF heavier:
  // env and upgrade went to 9 MB each that way, on a repo that was
  // deliberately shrunk one release ago.
  return needed <= MAX_H ? Math.max(MIN_H, needed) : MIN_H;
};

type Item = {id: string; cmd: string; lines: string[]};

export const RemotionRoot: React.FC = () => (
  <>
    {(data as Item[]).map((d) => {
      const dur = d.cmd.length * TYPE + PAD + Math.max(1, d.lines.length) * REVEAL + HOLD;
      return (
        <Composition
          key={d.id}
          id={d.id}
          component={Terminal}
          durationInFrames={dur}
          fps={FPS}
          width={900}
          height={heightFor(d.lines.length)}
          defaultProps={{cmd: d.cmd, lines: d.lines} satisfies TerminalProps}
        />
      );
    })}
  </>
);
