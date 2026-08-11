# Security policy

## Supported versions

Security fixes are released for the latest 1.x version. If a report also
affects the newest 0.x release, a backport may be published when the fix is
small and the affected application cannot upgrade immediately.

## Reporting a vulnerability

Please do not open a public issue for a vulnerability. Use
[GitHub private vulnerability reporting](https://github.com/yshmarov/testimonials/security/advisories/new)
and include the affected version, a minimal reproduction, impact, and any known
workaround. Do not include credentials, session cookies, private application
URLs, customer submissions, uploaded media, or production database contents.

Public disclosure should wait until a fixed version is available and affected
users have had a reasonable opportunity to upgrade.

## Data and deployment boundary

The public collection pages and widget are controlled by `config.enabled`;
the dashboard is separately protected by `authorize_admin` and fails closed
outside development until the host grants access. `config.public_api` is off by
default. When enabled, it serves only approved testimonials carrying public
consent and never serializes email or `author_id`.

Testimonials can store their text, rating, best line, moderation status,
consent choice and exact consent-text snapshot, attribution, source, page URL,
user agent, locale, tenant key, timestamps, and optional video, poster, and
avatar uploads. Page URLs are accepted only as HTTP(S) and stored without query
strings or fragments. NPS responses can store the score, comment, attribution,
the same query-free page URL, user agent, locale, tenant key, and timestamps.
Prompt events store the prompt kind/action, author id or pseudonymous visitor
token, tenant key, and timestamps.

Uploaded media streams through the engine's authorization gate with private,
non-stored responses; the route never redirects to a reusable signed blob URL.
Hosts own the storage service, bucket policy, backups, retention periods,
access controls, and incident response. Enabling the public API deliberately
makes approved, publicly consented testimonial media readable to anyone who
has its engine URL.

Delete records when an application policy or customer request requires it:

```ruby
Testimonials::Testimonial.find(id).destroy!
Testimonials::NpsResponse.find(id).destroy!
Testimonials::PromptEvent.where(author_id: user.id.to_s).delete_all
```

Destroying a testimonial lets Rails apply its configured Active Storage
attachment lifecycle. Confirm deletion separately in object storage, replicas,
backups, caches, analytics, notifications, and exports; deleting live database
rows does not rewrite those systems. Consent is evidence of the choice made at
submission time, not a substitute for the host's withdrawal and retention
process.
