import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Hex SHA-256 of a request body, for the `x-amz-content-sha256` header.
///
/// CloudFront's Lambda OAC sigv4-signs every origin request but cannot
/// hash a request body it streams through, and OAC-signed Lambda Function
/// URLs reject unsigned payloads — so the client must supply the payload
/// hash on any request that carries a body, or the Function URL answers
/// 403 before invocation (issue #590 defect 3). Every POST through a
/// CloudFront Lambda behavior (`/api/coach*`) must send this header over
/// the exact bytes of the body it posts. GETs carry no body and need
/// nothing. Twin of `apps/web/src/lib/util/payload_hash.ts`.
String payloadSha256Hex(String body) =>
    sha256.convert(utf8.encode(body)).toString();
