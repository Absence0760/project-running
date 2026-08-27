// The globals and event shape of the `cloudfront-js-2.0` runtime, so the
// functions beside this file are typechecked against the runtime they
// actually run in rather than against Node or a browser. Declarations only —
// nothing here is uploaded; Terraform reads each function's `.js` by name.
//
// Deliberately narrow. The runtime is ECMAScript 5.1 plus a subset of later
// features and has no `Promise`, no timers, no `fetch` and no module system,
// which `tsconfig.cloudfront.json` expresses with `lib: es5` and `types: []`.
// This file adds back only what CloudFront documents as present, so reaching
// for anything else is an error here instead of a 5xx at the edge.

declare const console: {
	log(...args: unknown[]): void;
	error(...args: unknown[]): void;
	warn(...args: unknown[]): void;
};

/**
 * A header, cookie or query-string entry. `multiValue` is present only when
 * the name occurred more than once; `value` then repeats its first element.
 */
interface CloudFrontValue {
	value?: string;
	multiValue?: { value: string }[];
}

type CloudFrontValueMap = Record<string, CloudFrontValue>;

interface CloudFrontRequest {
	method: string;
	uri: string;
	querystring: CloudFrontValueMap;
	headers: CloudFrontValueMap;
	cookies: CloudFrontValueMap;
}

interface CloudFrontResponse {
	statusCode: number;
	statusDescription?: string;
	headers?: CloudFrontValueMap;
	cookies?: CloudFrontValueMap;
	body?: string | { encoding?: 'text' | 'base64'; data: string };
}

interface CloudFrontEvent {
	version: string;
	context: {
		distributionDomainName: string;
		distributionId: string;
		eventType: 'viewer-request' | 'viewer-response';
		requestId: string;
	};
	viewer: { ip: string };
	request: CloudFrontRequest;
	response?: CloudFrontResponse;
}
