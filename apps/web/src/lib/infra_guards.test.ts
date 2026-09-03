// The shape of the deployed estate, read out of Terraform. These guards
// assert what the account and the distribution are configured to do —
// price class, log retention, WAF association, budget thresholds, the
// response headers CloudFront adds, and the auth on every Function URL —
// because none of it is reachable from a running test.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

function tfResources(src: string, type: string): Array<{ label: string; body: string }> {
	const out: Array<{ label: string; body: string }> = [];
	const header = new RegExp(`^resource "${type}" "([A-Za-z0-9_-]+)" \\{$`, 'gm');
	let m: RegExpExecArray | null;
	while ((m = header.exec(src))) {
		const rest = src.slice(m.index + m[0].length);
		const next = rest.search(/^resource "/m);
		out.push({ label: m[1], body: next < 0 ? rest : rest.slice(0, next) });
	}
	return out;
}

test('prod env wires alert_emails into the web-stack module', () => {
	// Reason: prod has tight validation on var.alert_emails (non-empty
	// + placeholder-rejected) but if main.tf didn't pass the variable
	// through, the module would default to [] and alarms would fire
	// into an empty SNS topic. The wire is the load-bearing link.
	const prodMain = read('../../infra/envs/prod/main.tf');
	const prodVars = read('../../infra/envs/prod/variables.tf');
	assert.match(
		prodMain,
		/alert_emails\s*=\s*var\.alert_emails/,
		'infra/envs/prod/main.tf must pass alert_emails into the web-stack module — without the wire, validated input never reaches the alarm subscribers.',
	);
	assert.match(
		prodVars,
		/variable\s+"alert_emails"[\s\S]*?validation\s*\{[\s\S]*?length\(var\.alert_emails\)\s*>\s*0/,
		'infra/envs/prod/variables.tf alert_emails must have a non-empty-list validation block.',
	);
	// Placeholder-rejection check accepts either the `endswith`
	// form or the `can(regex())` form used in prod today. Either is
	// acceptable; the load-bearing property is "rejects @example.com".
	assert.match(
		prodVars,
		/variable\s+"alert_emails"[\s\S]*?(endswith\(e,\s*"@example\.com"\)|@example\\?\.com)/,
		'infra/envs/prod/variables.tf alert_emails must reject @example.com placeholders (via endswith or regex match).',
	);
});

test('preview env declares alert_emails with non-empty validation', () => {
	// Reason: preview was the lone outlier — module default of [] +
	// no env-level validation meant alarms fired into an empty SNS
	// topic. A hit Lambda concurrency cap on a fresh preview env
	// went silent. /audit/cost-controls May 2026 closeout.
	const previewMain = read('../../infra/envs/preview/main.tf');
	const previewVars = read('../../infra/envs/preview/variables.tf');
	assert.match(
		previewMain,
		/alert_emails\s*=\s*var\.alert_emails/,
		'infra/envs/preview/main.tf must pass alert_emails into the web-stack module — closes the gap that /audit/cost-controls flagged.',
	);
	assert.match(
		previewVars,
		/variable\s+"alert_emails"[\s\S]*?validation\s*\{[\s\S]*?length\(var\.alert_emails\)\s*>\s*0/,
		'infra/envs/preview/variables.tf alert_emails must validate non-empty list.',
	);
});

test('web-stack CloudFront uses PriceClass_100 or PriceClass_200, never _All', () => {
	// Reason: PriceClass_All bills from every edge location, including
	// SA + AU which 10x the per-GB cost. A user accidentally toggling
	// the price class to _All in a "let's see if it's faster" experiment
	// produces a multi-x bill jump that doesn't get caught until end
	// of month.
	const mainTf = read('../../infra/modules/web-stack/main.tf');
	const priceClassMatch = mainTf.match(/price_class\s*=\s*"(PriceClass_\w+)"/);
	assert.ok(priceClassMatch, 'Could not locate price_class assignment in web-stack/main.tf.');
	assert.ok(
		['PriceClass_100', 'PriceClass_200'].includes(priceClassMatch![1]),
		`CloudFront price_class must be PriceClass_100 or PriceClass_200 (was "${priceClassMatch![1]}"). _All bills from every edge location regardless of where users live and 10× the per-GB cost.`,
	);
});

test('web-stack log groups all set retention_in_days', () => {
	// Reason: AWS CloudWatch Logs defaults to "Never expire" — that's
	// $0.50/GB/month forever for every log byte ever written. A
	// retention attribute on every aws_cloudwatch_log_group resource
	// caps the per-GB exposure to the configured window.
	const mainTf = read('../../infra/modules/web-stack/main.tf');
	// Find every aws_cloudwatch_log_group block and assert it sets
	// retention_in_days. The body grep is generous — exact-attribute
	// match would be fragile against HCL formatting variants.
	const logGroupRe = /resource\s+"aws_cloudwatch_log_group"\s+"[^"]+"\s*\{[\s\S]*?\n\}/g;
	const blocks = mainTf.match(logGroupRe) ?? [];
	assert.ok(
		blocks.length > 0,
		'Could not find any aws_cloudwatch_log_group blocks in web-stack/main.tf — has the resource moved?',
	);
	for (const block of blocks) {
		assert.match(
			block,
			/retention_in_days\s*=\s*\d+/,
			'Every aws_cloudwatch_log_group MUST set retention_in_days — default "Never expire" is $0.50/GB/month forever.\nBlock:\n' + block.slice(0, 200) + '…',
		);
	}
});

test('web-stack WAF web_acl_id wires the distribution + scope-down filters /api/coach', () => {
	// Reason: the WAF rate-limit rule fires per IP over a 5-min window
	// (limit = var.waf_rate_limit; prod passes 30, module default 100);
	// without the scope-down filter it would rate-limit ALL traffic
	// (static assets included), throttling legitimate users on the
	// first page load. Without the web_acl_id wire it wouldn't fire
	// at all. Both must be present together.
	const mainTf = read('../../infra/modules/web-stack/main.tf');
	const wafTf = read('../../infra/modules/web-stack/waf.tf');
	assert.match(
		mainTf,
		/web_acl_id\s*=\s*var\.waf_enabled[\s\S]*?aws_wafv2_web_acl\.coach\[0\]\.arn/,
		'CloudFront distribution must attach the WAF ACL via web_acl_id (gated on var.waf_enabled).',
	);
	// The scope-down statement must filter to /api/coach paths only.
	assert.match(
		wafTf,
		/scope_down_statement[\s\S]*?byte_match_statement[\s\S]*?\/api\/coach/,
		'WAF rate-limit rule must have a scope_down_statement byte-matching /api/coach so static-asset traffic isn\'t rate-limited.',
	);
});

test('AWS Budgets carries all three thresholds (50% ACTUAL, 100% ACTUAL, 100% FORECASTED)', () => {
	// Reason: the FORECASTED notification is the only one that catches
	// a runaway DURING the month — the two ACTUAL notifications fire
	// only after the spend lands on the bill (up to 24 h lag). A
	// budget that drops the FORECASTED notification leaves a 24 h
	// window where a leaked Anthropic key can rack up hundreds of
	// dollars before anyone notices.
	const budgets = read('../../infra/envs/prod/budgets.tf');
	const notifications = budgets.match(/notification\s*\{[\s\S]*?\}/g) ?? [];
	assert.ok(
		notifications.length >= 3,
		`Expected ≥3 notification blocks in budgets.tf, found ${notifications.length}. The 50%/100% ACTUAL + 100% FORECASTED set is the documented baseline.`,
	);
	// Pin each of the three required types/thresholds.
	const has = (re: RegExp): boolean => notifications.some((n) => re.test(n));
	assert.ok(
		has(/threshold\s*=\s*50[\s\S]*?notification_type\s*=\s*"ACTUAL"/),
		'budgets.tf must declare a 50% ACTUAL notification — early warning at half-budget.',
	);
	assert.ok(
		has(/threshold\s*=\s*100[\s\S]*?notification_type\s*=\s*"ACTUAL"/),
		'budgets.tf must declare a 100% ACTUAL notification — budget blown.',
	);
	assert.ok(
		has(/threshold\s*=\s*100[\s\S]*?notification_type\s*=\s*"FORECASTED"/),
		'budgets.tf must declare a 100% FORECASTED notification — the ONLY one that catches a runaway during the month (the 24h-lagged ACTUAL fires too late).',
	);
});

test('CloudFront CSP drops unsafe-eval and bounds XSS gadget surface', () => {
	// Reason: pass-2 hardening (commit 624bc00) tightened the CSP on
	// the CloudFront response-headers policy. unsafe-eval is gone (the
	// static SvelteKit build does not eval); object-src 'none',
	// base-uri 'self', form-action 'self', frame-ancestors 'none' all
	// bound the surface an XSS gadget could reach. Reverting any one
	// reopens a class of attack:
	//   - object-src: SVG-embedded scripts via <object>/<embed>
	//   - base-uri: <base href> redirect of every relative URL
	//   - form-action: form data exfiltration to attacker-origin
	//   - frame-ancestors: clickjack via <iframe> embed
	const tf = read('../../infra/modules/web-stack/main.tf');
	// Find the content_security_policy block.
	const cspMatch = tf.match(
		/content_security_policy\s*=\s*join\([^)]*?\[([\s\S]*?)\]\s*\)/m,
	);
	assert.ok(
		cspMatch,
		'Could not locate content_security_policy in infra/modules/web-stack/main.tf — has it been restructured?',
	);
	const csp = cspMatch![1];
	assert.doesNotMatch(
		csp,
		/'unsafe-eval'/,
		"CSP must not include 'unsafe-eval' — the static SvelteKit build does not eval. Pass-2 commit 624bc00.",
	);
	for (const directive of [
		'object-src',
		'base-uri',
		'form-action',
		'frame-ancestors',
	]) {
		assert.match(
			csp,
			new RegExp(directive),
			`CSP must include the ${directive} directive — pass-2 commit 624bc00.`,
		);
	}
	// Sentry browser SDK posts errors here — without this connect-src
	// entry, every Sentry breadcrumb is silently CSP-blocked
	// (regression caught by /audit/infra M2).
	assert.match(
		csp,
		/\*\.ingest\.sentry\.io/,
		'CSP connect-src must include https://*.ingest.sentry.io — Sentry browser SDK posts errors there.',
	);
});

test('both CSP layers allow MapLibre blob: workers (worker-src)', () => {
	// Reason: MapLibre GL spawns its tile-processing Web Worker from a
	// blob: URL. A document must satisfy BOTH the CloudFront header CSP
	// AND the SvelteKit <meta> CSP, so BOTH must allow blob: workers or
	// every map renders blank. The audit-xss M2 hash-mode <meta> CSP
	// (commit 8cddf96c) tightened script-src to 'self' + hashes but
	// omitted worker-src, so the blob worker fell back to script-src and
	// was blocked — the entire heatmap / run-map surface broke
	// (run 26822355308). Pin worker-src blob: in both layers.
	const tf = read('../../infra/modules/web-stack/main.tf');
	assert.match(
		tf,
		/worker-src[^"]*blob:/,
		'CloudFront header CSP must allow worker-src blob: for MapLibre.',
	);
	const sv = read('svelte.config.js');
	const directives = sv.match(/directives:\s*\{([\s\S]*?)\}/);
	assert.ok(directives, 'Could not locate the SvelteKit csp.directives block.');
	assert.match(
		directives![1],
		/'worker-src':\s*\[[^\]]*'blob:'/,
		"SvelteKit <meta> CSP directives must include 'worker-src': [..., 'blob:'] " +
			'or MapLibre workers are blocked (the stricter of the two CSP layers wins).',
	);
});

test('CloudFront Permissions-Policy disables sensors / payment / FLoC + Privacy Sandbox', () => {
	// Reason: pass-2 commit 624bc00 added a Permissions-Policy header
	// disabling APIs the app doesn't use. An XSS-injected
	// `document.browsingTopics()` would otherwise execute and leak the
	// user's interest cohort; same for accelerometer / geolocation
	// (cross-origin contexts) / payment-request-API-driven phishing.
	const tf = read('../../infra/modules/web-stack/main.tf');
	const ppMatch = tf.match(
		/header\s*=\s*"Permissions-Policy"[\s\S]*?value\s*=\s*"([^"]+)"/m,
	);
	assert.ok(
		ppMatch,
		'Could not locate the Permissions-Policy custom header in infra/modules/web-stack/main.tf.',
	);
	const policy = ppMatch![1];
	for (const directive of [
		'accelerometer',
		'attribution-reporting',
		'browsing-topics',
		'camera',
		'gyroscope',
		'interest-cohort',
		'magnetometer',
		'microphone',
		'payment',
		'usb',
	]) {
		assert.match(
			policy,
			new RegExp(`${directive}=\\(\\)`),
			`Permissions-Policy must disable ${directive} — pass-2 commit 624bc00.`,
		);
	}
});

// Every top-level `resource "<type>" "<label>" { … }` in a Terraform file, as
// `{ label, body }`. Deliberately a split on the header at column 0 rather than
// a brace-matching parse: nothing here is HCL evaluation, and every resource in
// this module is top-level, so the next header is the end of the previous body.

test('EVERY Lambda Function URL is AWS_IAM-auth + CloudFront-only', () => {
	// Reason: pass-1 /audit/infra H3 (commit 6614d89) flipped the
	// Function URL from authorization_type=NONE to AWS_IAM and added
	// a CloudFront OAC of type "lambda" that signs every request.
	// Reverting any of these makes the .lambda-url.* hostname directly
	// reachable by anyone — bypasses CloudFront, the WAF tier, and
	// every CSP / per-IP guard the distribution applies.
	//
	// This used to be four `/aws_lambda_function_url[\s\S]*?authorization_type
	// = "AWS_IAM"/` matches against the whole file, which say only that SOME
	// Function URL somewhere is AWS_IAM and SOME permission somewhere names
	// CloudFront. The module holds eight of each. Measured: appending a ninth
	// Function URL with `authorization_type = "NONE"`, and a ninth permission
	// with `principal = "*"`, left this test green — the exact regression it is
	// written to catch, on the exact resource type it names. Read per resource
	// instead, so the assertion is about all of them.
	const tf = read('../../infra/modules/web-stack/main.tf');

	const urls = tfResources(tf, 'aws_lambda_function_url');
	assert.ok(urls.length >= 8, `read only ${urls.length} Function URLs — parser broken?`);
	for (const { label, body } of urls) {
		assert.match(
			body,
			/^\s*authorization_type\s*=\s*"AWS_IAM"$/m,
			`aws_lambda_function_url.${label} must use authorization_type=AWS_IAM — anything else ` +
				'makes its .lambda-url.* hostname world-invocable, bypassing CloudFront and the WAF.',
		);
	}

	const oacs = tfResources(tf, 'aws_cloudfront_origin_access_control');
	assert.ok(
		oacs.some((o) => /origin_access_control_origin_type\s*=\s*"lambda"/.test(o.body)),
		'CloudFront must have an origin_access_control of type "lambda" so it sigv4-signs every Function URL request.',
	);
	for (const { label, body } of oacs) {
		assert.match(
			body,
			/signing_behavior\s*=\s*"always"/,
			`aws_cloudfront_origin_access_control.${label} must sign always — "never" leaves the ` +
				'origin reached unsigned, which an AWS_IAM Function URL then rejects and the SPA ' +
				'fallback hides behind a 200 shell.',
		);
	}

	const permissions = tfResources(tf, 'aws_lambda_permission');
	assert.ok(
		permissions.length >= 16,
		`read only ${permissions.length} lambda permissions — parser broken?`,
	);
	for (const { label, body } of permissions) {
		assert.match(
			body,
			/^\s*principal\s*=\s*"cloudfront\.amazonaws\.com"$/m,
			`aws_lambda_permission.${label} must restrict principal to cloudfront.amazonaws.com ` +
				'(was * before pass-1 /audit/infra H3).',
		);
		if (/action\s*=\s*"lambda:InvokeFunctionUrl"/.test(body)) {
			assert.match(
				body,
				/^\s*function_url_auth_type\s*=\s*"AWS_IAM"$/m,
				`aws_lambda_permission.${label} grants InvokeFunctionUrl and must declare ` +
					'function_url_auth_type=AWS_IAM.',
			);
		}
	}
});

// The three operator scripts that address the estate secrets file all have to
// agree about two strings: where the file lives, and what the not-yet-wired
// placeholder in the estate `.sops.yaml` is called. `sops-init.sh` writes the
// placeholder, `secret-set.sh` writes into the file, and `key-rotate.sh` reads
// the rule back to decide which key the file should be under.
//
// key-rotate.sh had gone stale on both. It anchored on `<env>/secrets` and
// recognised `REPLACE_<ENV>_KMS_ARN`, which are the in-repo layout from before
// the secrets moved to the estate repo; neither string occurs in the estate
// config, so BOTH envs matched no rule and the script died claiming an
// unresolved placeholder — including on prod, whose key is fully wired — and
// sent the operator to re-run sops-init.sh, which would tell them it was
// already resolved. Key rotation is the compromise-response path, so it being
// unconditionally broken is exactly the thing nobody discovers in advance.

test('S3 site bucket lifecycle aborts incomplete multipart uploads', () => {
	// Reason: pass-2 commit 624bc00 added an abort-incomplete-multipart
	// lifecycle rule. Without it an interrupted deploy (CI killed
	// mid-upload) leaks storage forever — multipart parts don't show
	// in `aws s3 ls` so they're invisible to operators but accrue cost.
	const tf = read('../../infra/modules/web-stack/main.tf');
	assert.match(
		tf,
		/abort_incomplete_multipart_upload[\s\S]*?days_after_initiation\s*=\s*\d+/,
		'site bucket must have an abort_incomplete_multipart_upload lifecycle rule — pass-2 commit 624bc00.',
	);
});

test('OIDC deploy roles carry default Project / Stack / ManagedBy tags', () => {
	// Reason: pass-2 commit 624bc00 synthesised default tags via a
	// `oidc_tags` local so callers don't have to remember to set them.
	// Cost-allocation reports + blast-radius audits depend on every
	// resource in the OIDC stack carrying these — silent drift is the
	// regression to catch.
	const tf = read('../../infra/github-oidc/main.tf');
	const localsMatch = tf.match(/locals\s*\{[\s\S]*?oidc_tags\s*=\s*merge\(\s*\{([\s\S]*?)\}/);
	assert.ok(localsMatch, 'Could not locate oidc_tags merge() in infra/github-oidc/main.tf.');
	const tags = localsMatch![1];
	for (const key of ['Project', 'Stack', 'ManagedBy']) {
		assert.match(
			tags,
			new RegExp(`${key}\\s*=`),
			`oidc_tags local must include the ${key} default — pass-2 commit 624bc00.`,
		);
	}
	// Each deploy role must apply Environment via merge so prod /
	// preview spend is distinguishable.
	assert.match(
		tf,
		/aws_iam_role"\s+"deploy_prod"[\s\S]*?tags\s*=\s*merge\(local\.oidc_tags,\s*\{\s*Environment\s*=\s*"prod"/,
		'deploy_prod role must merge oidc_tags with Environment="prod".',
	);
	assert.match(
		tf,
		/aws_iam_role"\s+"deploy_preview"[\s\S]*?tags\s*=\s*merge\(local\.oidc_tags,\s*\{\s*Environment\s*=\s*"preview"/,
		'deploy_preview role must merge oidc_tags with Environment="preview".',
	);
});
