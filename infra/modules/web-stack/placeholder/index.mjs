// Placeholder Lambda — Terraform creates the function pointing at a
// zip of this file so the AWS Function URL resource has something to
// reference. CI's first `web@*` deploy replaces it with the real
// bundle from `apps/web/lambda/coach/build.mjs`.
//
// Until then, any request returns 503 with a hint pointing at the
// release pipeline.

export const handler = async () => ({
	statusCode: 503,
	headers: { 'content-type': 'application/json' },
	body: JSON.stringify({
		error: 'coach_not_deployed',
		message: 'Coach Lambda has not been deployed yet. Push a `web@*` tag to release.',
	}),
});
