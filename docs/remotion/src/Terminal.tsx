import React from 'react';
import {AbsoluteFill, useCurrentFrame, useVideoConfig} from 'remotion';
import {loadFont} from '@remotion/google-fonts/JetBrainsMono';

const {fontFamily} = loadFont('normal', {weights: ['400', '700']});

const T = {
  bg: '#0b0e14', fg: '#bfbdb6', header: '#ffb454', ok: '#7fd962',
  err: '#f26d78', warn: '#e6b450', dim: '#5c6773', cmd: '#73d0ff', prompt: '#7fd962',
};

const FONT_SIZE = 21;
const LH = 30;
const TYPE = 2;
const PAD = 6;
const REVEAL = 4;
const HEADER_H = 96;
// Padding above and below (34 each) plus the 8px gap under the prompt: what
// is left of the composition is what the output can occupy. This used to be a
// fixed 15 lines, which scrolled a fixture off its own first line even when
// the frame was tall enough to hold all of it.
const OUTPUT_INSET = 34 * 2 + 8;

export type TerminalProps = {cmd: string; lines: string[]};

const lineStyle = (raw: string): React.CSSProperties => {
  const s = raw.trim();
  if (/^(--|==)/.test(s)) return {color: T.header, fontWeight: 700};
  if (/^\[\d+\/\d+\]/.test(s)) return {color: T.dim};
  if (s.includes('✗')) return {color: T.err};
  if (s.includes('⚠')) return {color: T.warn};
  if (s.includes('✓')) return {color: T.ok};
  if (s.startsWith('|') || s.startsWith('+') || s.startsWith('─')) return {color: T.dim};
  if (/Disabled|Error|FAIL/.test(s)) return {color: T.warn};
  return {color: T.fg};
};

export const Terminal: React.FC<TerminalProps> = ({cmd, lines}) => {
  const frame = useCurrentFrame();
  const typed = Math.min(cmd.length, Math.max(0, Math.floor(frame / TYPE)));
  const typeEnd = cmd.length * TYPE + PAD;
  // Clamped: without the cap, shown keeps counting through the hold at the end
  // and scrolls the output up past its own last line, so every GIF ended on a
  // drifted frame rather than on the finished report.
  const shown = Math.min(lines.length, Math.max(0, Math.floor((frame - typeEnd) / REVEAL)));
  const blink = Math.floor(frame / 15) % 2 === 0;
  const {height} = useVideoConfig();
  const visible = Math.max(1, Math.floor((height - HEADER_H - OUTPUT_INSET) / LH));
  const scroll = Math.max(0, shown - visible) * LH;

  return (
    <AbsoluteFill style={{backgroundColor: T.bg, fontFamily, fontSize: FONT_SIZE, padding: 34, overflow: 'hidden'}}>
      <div style={{display: 'flex', gap: 9, marginBottom: 26}}>
        <div style={{width: 14, height: 14, borderRadius: 7, background: '#f26d78'}} />
        <div style={{width: 14, height: 14, borderRadius: 7, background: '#e6b450'}} />
        <div style={{width: 14, height: 14, borderRadius: 7, background: '#7fd962'}} />
      </div>
      <div style={{whiteSpace: 'pre', lineHeight: `${LH}px`}}>
        <span style={{color: T.prompt}}>❯ </span>
        <span style={{color: T.cmd}}>{cmd.slice(0, typed)}</span>
        {typed < cmd.length && blink ? <span style={{background: T.fg, color: T.bg}}>&nbsp;</span> : null}
      </div>
      <div style={{position: 'relative', height: `calc(100% - ${HEADER_H}px)`, overflow: 'hidden', marginTop: 8}}>
        <div style={{transform: `translateY(${-scroll}px)`}}>
          {lines.slice(0, shown).map((l, i) => (
            <div key={i} style={{whiteSpace: 'pre', lineHeight: `${LH}px`, ...lineStyle(l)}}>
              {l.length ? l : ' '}
            </div>
          ))}
        </div>
      </div>
    </AbsoluteFill>
  );
};
