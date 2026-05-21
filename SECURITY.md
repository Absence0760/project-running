# Security policy

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security reports.
Instead, send the details to the project owner via GitHub's private
security advisory flow:

  https://github.com/Absence0760/project-running/security/advisories/new

When reporting, include:

- A concise description of the issue
- The component or surface affected (web app, Supabase Edge Function,
  job worker, mobile, watch, infra)
- Steps to reproduce, ideally a minimal proof of concept
- The expected vs. observed behaviour
- Any logs or screenshots that help triage

We aim to acknowledge new reports within 3 business days. Critical
issues affecting authentication, authorization, payment, or PII
handling are prioritised over hardening suggestions.

## Scope

In scope: anything under this repository. Where the issue spans this
repo and an upstream dependency, we will coordinate with the upstream
maintainer once the impact here is understood.

Out of scope: denial-of-service tests against threkir.com,
brute-force credential stuffing, social-engineering attempts, or
issues that require physical access to a user's device.

## Disclosure

Coordinated disclosure once a fix is rolled out and (where
applicable) users have been notified. We will credit the reporter in
the release notes unless they ask to remain anonymous.

## Supported versions

The latest tag on `main` is the only supported release. Older tags
are kept for audit but no longer receive security backports.
