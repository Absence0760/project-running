import test from 'node:test';
import assert from 'node:assert/strict';

import { splitShellCommands } from './shell_lex.mjs';

/** @param {string} src */
const words = (src) => splitShellCommands(src).map((c) => c.words);

test('splits on every operator a shell splits on', () => {
	assert.deepEqual(words('a b; c d && e f || g h | i j & k'), [
		['a', 'b'],
		['c', 'd'],
		['e', 'f'],
		['g', 'h'],
		['i', 'j'],
		['k'],
	]);
});

// The three false accusations, each from one real shape.
test('a semicolon does not become part of the word before it', () => {
	assert.deepEqual(words('cd apps/backend; supabase db reset'), [
		['cd', 'apps/backend'],
		['supabase', 'db', 'reset'],
	]);
});

test('quotes come off the word rather than staying in it', () => {
	assert.deepEqual(words('cd "apps/web" && cd \'apps/backend\''), [
		['cd', 'apps/web'],
		['cd', 'apps/backend'],
	]);
});

test('a flag is a word of its own, not the argument after it', () => {
	assert.deepEqual(words('pnpm -C apps/web --silent run check'), [
		['pnpm', '-C', 'apps/web', '--silent', 'run', 'check'],
	]);
});

test('command substitution is a command, not a word', () => {
	assert.deepEqual(words('CURRENT=$(aws lambda get-alias --name live)'), [
		['CURRENT=$'],
		['aws', 'lambda', 'get-alias', '--name', 'live'],
	]);
});

test('a backslash joins the next line into the same command', () => {
	assert.deepEqual(words('aws lambda update-alias \\\n  --name live \\\n  --function-version 3'), [
		['aws', 'lambda', 'update-alias', '--name', 'live', '--function-version', '3'],
	]);
});

test('a newline ends the command', () => {
	assert.deepEqual(words('cd a\ncd b'), [
		['cd', 'a'],
		['cd', 'b'],
	]);
});

test('a comment runs to end of line, and only where a word may begin', () => {
	assert.deepEqual(words('cd a # cd nowhere\ncd b'), [
		['cd', 'a'],
		['cd', 'b'],
	]);
	assert.deepEqual(words('git log --format=%h#%s'), [['git', 'log', '--format=%h#%s']]);
});

test('nothing is expanded — the text written is the text returned', () => {
	assert.deepEqual(words('NAME="threkir-web-${ENV}-coach"'), [['NAME=threkir-web-${ENV}-coach']]);
});

test('single quotes take no escapes, double quotes do', () => {
	assert.deepEqual(words("echo 'a\\b'"), [['echo', 'a\\b']]);
	assert.deepEqual(words('echo "a\\"b"'), [['echo', 'a"b']]);
});

// A fragment the lexer cannot read is one no guard may report a verdict about.
test('an unterminated quote throws rather than being consumed to end of input', () => {
	assert.throws(() => splitShellCommands("cd 'apps/web"), /unterminated/);
	assert.throws(() => splitShellCommands('cd "apps/web'), /unterminated/);
});

test('each command carries the line it starts on', () => {
	assert.deepEqual(splitShellCommands('a\n\nb \\\nc\nd'), [
		{ line: 1, words: ['a'] },
		{ line: 3, words: ['b', 'c'] },
		{ line: 5, words: ['d'] },
	]);
});
