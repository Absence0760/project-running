import assert from 'node:assert/strict';
import test from 'node:test';

import { blockEnd, hclBlocks, hclResources, nestedBlock } from './hcl_lex.mjs';

// The three shapes a regex gets wrong on this repo's own Terraform, all of
// which appear in infra/modules/web-stack/main.tf: an interpolated string
// carrying a brace, a comment carrying an unbalanced one, and a nested block.
const REAL_SHAPES = `
# A comment whose stray brace { never closes.
resource "aws_lambda_function" "coach" {
  function_name = "\${local.resource_prefix}-coach"
  environment {
    variables = {
      FOO = "bar"
    }
  }
}

resource "aws_lambda_function" "share_run" {
  function_name = "\${local.resource_prefix}-share-run"
}
`;

test('hclResources reads past interpolated braces and unbalanced comments', () => {
  const found = hclResources(REAL_SHAPES, 'aws_lambda_function');
  assert.deepEqual(
    found.map((r) => r.label),
    ['coach', 'share_run'],
  );
  assert.match(found[0].body, /environment \{/);
  assert.match(found[1].body, /share-run/);
  // The first body must stop at its own closing brace, not swallow the second.
  assert.doesNotMatch(found[0].body, /share_run/);
});

test('hclResources returns nothing for a type the source does not declare', () => {
  assert.deepEqual(hclResources(REAL_SHAPES, 'aws_s3_bucket'), []);
});

test('a block that never closes is dropped rather than half-read', () => {
  const truncated = 'resource "aws_iam_role" "deploy" {\n  name = "x"\n';
  assert.deepEqual(hclResources(truncated, 'aws_iam_role'), []);
  assert.equal(blockEnd(truncated, truncated.indexOf('{')), -1);
});

test('a quote inside a line comment does not open a string', () => {
  // Without comment handling the `"` below opens a string that swallows the
  // closing brace, and the resource reads as unterminated.
  const src =
    'resource "aws_iam_role" "deploy" {\n' +
    '  # the role formerly known as "deploy-old" {\n' +
    '  name = "deploy"\n' +
    '}\n';
  const [role] = hclResources(src, 'aws_iam_role');
  assert.ok(role, 'the role must be read despite the quote in the comment');
  assert.match(role.body, /name = "deploy"/);
});

test('an escaped quote does not end the string early', () => {
  const src =
    'resource "aws_iam_role" "deploy" {\n' +
    '  description = "a \\" brace } inside a string"\n' +
    '}\n';
  const [role] = hclResources(src, 'aws_iam_role');
  assert.ok(role);
  assert.match(role.body, /description/);
});

test('a block comment hides its braces from the scan', () => {
  const src =
    'resource "aws_iam_role" "deploy" {\n' +
    '  /* } */\n' +
    '  name = "deploy"\n' +
    '}\n';
  const [role] = hclResources(src, 'aws_iam_role');
  assert.ok(role);
  assert.match(role.body, /name = "deploy"/);
});

test('hclBlocks reads a data block, not only a resource', () => {
  const src =
    'data "aws_iam_policy_document" "kms" {\n  statement {\n    sid = "S"\n  }\n}\n';
  const [doc] = hclBlocks(src, 'data', 'aws_iam_policy_document');
  assert.equal(doc.label, 'kms');
  assert.match(doc.body, /sid = "S"/);
});

test('nestedBlock returns the matching inner body, and null when absent', () => {
  const body =
    '  Condition = {\n' +
    '    StringEquals = {\n' +
    '      "aud" = "sts.amazonaws.com"\n' +
    '    }\n' +
    '  }\n';
  assert.match(nestedBlock(body, /StringEquals\s*=\s*\{/) ?? '', /sts\.amazonaws/);
  assert.equal(nestedBlock(body, /StringLike\s*=\s*\{/), null);
});

test('nestedBlock is not confused by a global regex', () => {
  const body = 'A = {\n  x = 1\n}\nA = {\n  y = 2\n}\n';
  assert.match(nestedBlock(body, /A\s*=\s*\{/g) ?? '', /x = 1/);
});
