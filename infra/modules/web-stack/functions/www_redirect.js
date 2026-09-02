// CloudFront Function (viewer-request): permanently redirect a `www.` host to
// the bare apex, preserving the method, path and query string. Both
// `www.threkir.com` and `threkir.com` are aliases on the same distribution and
// otherwise serve byte-identical content — a duplicate-content signal split.
// Consolidating onto the apex with a permanent redirect is the durable fix
// (canonical tags only mitigate per page, and not every SPA route emits one).
//
// Host-agnostic: strips a leading `www.` from whatever Host arrives, so the
// same code works for any apex the distribution is fronting (no domain baked
// in). Non-www hosts pass through untouched.
//
// The host is lowercased before both the test and the rebuild. A hostname is
// case-insensitive (RFC 9110 § 4.2.3, RFC 3986 § 3.2.2), so a client may send
// `WWW.threkir.com` and CloudFront still routes it here and serves it; nothing
// in the event contract promises a lowercased header VALUE (only header NAMES
// are documented as normalised). A case-sensitive prefix test therefore left
// the whole site reachable at a second host, which is the exact split this
// function exists to close (decisions § 894).
//
// GET and HEAD keep the 301 crawlers have always seen. Everything else gets a
// 308: this function is associated with EVERY cache behaviour on the
// distribution, `/api/coach/*` included, and a 301 lets a client rewrite a
// POST into a bodiless GET (RFC 9110 § 15.4.2). 308 is the method-preserving
// permanent redirect and carries the same permanence signal.
//
// Runtime: cloudfront-js-2.0 — typechecked against it by
// `tsconfig.cloudfront.json`, whose `lib` and `types` describe that runtime
// rather than Node or a browser (decisions § 757). Behaviour is pinned by
// `www_redirect.test.mjs` beside this file.
/**
 * @param {CloudFrontEvent} event
 * @returns {CloudFrontRequest | CloudFrontResponse}
 */
function handler(event) {
	var request = event.request;
	var headers = request.headers;
	var rawHost = headers.host && headers.host.value ? headers.host.value : '';
	var host = rawHost.toLowerCase();

	if (host.indexOf('www.') !== 0) {
		return request;
	}

	var apex = host.substring(4);

	// Rebuild the query string from the parsed object (single + multi-value)
	// so params (UTM tags, share tokens, ?tab=) survive the redirect.
	var qs = request.querystring;
	var pairs = [];
	for (var key in qs) {
		var param = qs[key];
		if (param.multiValue) {
			for (var i = 0; i < param.multiValue.length; i++) {
				pairs.push(key + '=' + param.multiValue[i].value);
			}
		} else if (param.value !== undefined && param.value !== '') {
			pairs.push(key + '=' + param.value);
		} else {
			pairs.push(key);
		}
	}
	var query = pairs.length > 0 ? '?' + pairs.join('&') : '';

	var method = request.method ? request.method.toUpperCase() : 'GET';
	var safe = method === 'GET' || method === 'HEAD';

	return {
		statusCode: safe ? 301 : 308,
		statusDescription: safe ? 'Moved Permanently' : 'Permanent Redirect',
		headers: {
			location: { value: 'https://' + apex + request.uri + query },
		},
	};
}
