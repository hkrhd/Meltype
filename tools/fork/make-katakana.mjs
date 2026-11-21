// SPDX-License-Identifier: GPL-3.0-or-later
//
// JMdict (EDRDG、CC BY-SA 4.0) から、フォークで足す 3 音のカタカナ語 (スキル・アプデ) の読みの一覧 dictionaries/fork/katakana.txt を作る。
//   node tools/fork/make-katakana.mjs JMdict_e.xml > dictionaries/fork/katakana.txt
// upstream の tools/make-katakana.mjs は 3 文字以下を入れないので、3 文字のうち小書きのかなを含まない語 (3 音) だけを足す。
// 2 音以下 (ビュウ・ティン) は英単語の一部に現れやすい (adbyuu、thin) ので入れない。
import fs from 'node:fs';

const xml = fs.readFileSync(process.argv[2], 'utf8');
const toHiragana = s => s.replace(/[ァ-ヶ]/g, c => String.fromCharCode(c.charCodeAt(0) - 0x60));

const words = new Set();
for (const [, reb] of xml.matchAll(/<reb>([ァ-ヶー]+)<\/reb>/g)) {
  const reading = toHiragana(reb);
  if (reading.length === 3 && !/[ぁぃぅぇぉゃゅょゎゕゖ]/.test(reading)) words.add(reading);
}

const out = [
  '# Meltype フォーク: 3 音のカタカナ語の読みの一覧 (dictionaries/katakana.txt の後ろに続けて読む)',
  '# JMdict (Electronic Dictionary Research and Development Group) のカタカナだけの読みから tools/fork/make-katakana.mjs で作成。',
  '# JMdict は Creative Commons Attribution-ShareAlike 4.0 (CC BY-SA 4.0) で公開されている: https://www.edrdg.org/edrdg/licence.html',
  ...[...words].sort(),
];
process.stdout.write(out.join('\n') + '\n');
