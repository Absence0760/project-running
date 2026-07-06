// CloudFront Function (viewer-request): 301-redirect a `www.` host to the
// bare apex, preserving the path + query string. Both `www.threkir.com` and
// `threkir.com` are aliases on the same distribution and otherwise serve
// byte-identical content — a duplicate-content signal split. Consolidating
// onto the apex with a permanent redirect is the durable fix (canonical tags
// only mitigate per page, and not every SPA route emits one).
//
// Host-agnostic: strips a leading `www.` from whatever Host arrives, so the
// same code works for any apex the distribution is fronting (no domain baked
// in). Non-www hosts pass through untouched.
//
// Runtime: cloudfront-js-2.0.
function handler(event) {
	var request = event.request;
	var headers = request.headers;
	var host = headers.host && headers.host.value ? headers.host.value : '';

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

	return {
		statusCode: 301,
		statusDescription: 'Moved Permanently',
		headers: {
			location: { value: 'https://' + apex + request.uri + query },
		},
	};
}
