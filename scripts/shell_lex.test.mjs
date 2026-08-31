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

// decisions.md § 773 closed a decoy inside an alias call's own argument list —
// `--function-name "$(… --name live)" --name stable` reading `live`. The same
// decoy written with backticks was still live: the substitution stayed inside
// the enclosing command's words, so the decoy's `--name` came first.
test('a backtick substitution is a command of its own, not words of the one around it', () => {
	const cmds = splitShellCommands(
		'aws lambda update-alias --function-name `aws ssm get-parameter --name live` --name stable',
	);
	assert.deepEqual(cmds.map((c) => c.words), [
		['aws', 'lambda', 'update-alias', '--function-name'],
		['aws', 'ssm', 'get-parameter', '--name', 'live'],
		['--name', 'stable'],
	]);
	assert.ok(!cmds[0].words.includes('live'));
});

test('a backtick inside quotes stays inside its word, as `$(` already does', () => {
	assert.deepEqual(
		splitShellCommands('cmd --name "`inner --name live`" --name stable')[0].words,
		['cmd', '--name', '`inner --name live`', '--name', 'stable'],
	);
	assert.deepEqual(
		splitShellCommands("cmd --name '`inner`'")[0].words,
		['cmd', '--name', '`inner`'],
	);
});

test('a backtick in a comment opens no command', () => {
	assert.deepEqual(splitShellCommands('# see `aws lambda update-alias`\ncmd').map((c) => c.words), [
		['cmd'],
	]);
});

test('an escaped backtick is a character, not a boundary', () => {
	assert.deepEqual(splitShellCommands('cmd a\\`b')[0].words, ['cmd', 'a`b']);
});

// The shapes the two consuming guards meet in real scripts. None of these is a
// command a scan should act on, and each one used to be lexed as words of the
// command it sits in.
test('arithmetic expansion is a nested command, not a word of its host', () => {
	assert.deepEqual(splitShellCommands('echo $(( 1 + 2 ))').map((c) => c.words), [
		['echo', '$'],
		['1', '+', '2'],
	]);
});

test('a redirection target does not merge into the word before it', () => {
	assert.deepEqual(splitShellCommands('npm run build > out.txt')[0].words, [
		'npm',
		'run',
		'build',
		'>',
		'out.txt',
	]);
});

test('a variable assignment prefix stays with its command', () => {
	assert.deepEqual(splitShellCommands('FOO=bar cmd --flag')[0].words, ['FOO=bar', 'cmd', '--flag']);
});
