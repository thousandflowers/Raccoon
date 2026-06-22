import React from 'react';
import {Composition} from 'remotion';
import {Terminal, TerminalProps} from './Terminal';
import data from './data.json';

const FPS = 30;
const TYPE = 2, PAD = 6, REVEAL = 4, HOLD = 40;

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
          height={620}
          defaultProps={{cmd: d.cmd, lines: d.lines} satisfies TerminalProps}
        />
      );
    })}
  </>
);
