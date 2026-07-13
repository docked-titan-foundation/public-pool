# Security Policy

## Reporting Security Vulnerabilities

If you discover a security vulnerability in public-pool, please report it responsibly.
Do not report security issues via public GitHub issues or pull requests.

**Preferred method:** Email <security.emporium706@passmail.com>

Please include as much detail as possible:

- Type of vulnerability (e.g., buffer overflow, injection)
- Full paths of source file(s) related to the issue
- Steps to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact assessment

## Response Timeline

We aim to acknowledge security reports within 48 hours and provide a more detailed
response within 7 days.

## Supported Versions

| Version | Supported          |
| ------- | ----------------- |
| 1.x     | :white_check_mark: |
| 0.x     | :x:              |

## Disclosure Policy

Upon receiving a security report, we will:

1. Confirm the issue and assess severity
2. Identify affected versions
3. Prepare a fix for supported versions
4. Coordinate disclosure timeline with reporter
5. Release the fix as a security update

## Security Updates

Security fixes are released as patch updates and announced in the project release notes.

## Scope

This security policy applies to the public-pool Docker image and its included tools:

- Helm
- Helmfile
- kubectl
- Helm Diff
- Helm Secrets
- SOPS

Vulnerabilities in third-party tools bundled in the image should be reported to their
respective maintainers.

## Acknowledgments

We appreciate the efforts of security researchers who responsibly disclose vulnerabilities
in public-pool.
