# Supabase Auth provider setup

This repository does not provision third-party credentials or enable hosted providers. Configure each environment through the Supabase Dashboard or an authorized management workflow. Keep provider client secrets and signing keys in Supabase-managed Auth settings or an approved server-side secret manager; never place them in this repository, a client bundle, or logs.

## Apple

1. In the Apple Developer account, configure Sign in with Apple for the app identifier and create the Services ID and signing key required by the chosen app flow.
2. Configure the Supabase Auth callback URL shown for the target project as the Apple return URL. Configure the Supabase Apple provider with the client identifier(s) and generated secret in the Supabase Dashboard.
3. For Apple web OAuth, place the web Services ID first in the provider client-ID list. Keep the signing key private and plan to rotate the generated Apple client secret at Apple's required interval.

Apple native sign-in and browser OAuth have different client-ID/audience requirements. Configure only the identifiers required by the shipping clients. Supabase Auth currently handles Apple OAuth rather than Apple server-to-server notifications.

## Google

1. Create or select a Google Cloud project and configure the OAuth consent screen, audience, and minimum required scopes (`openid`, email, and profile as needed).
2. Create an OAuth client for the application. Register the application's authorized origin and the Supabase Auth callback URL shown for the target project as an authorized redirect URI.
3. Enter the client ID and secret in the Supabase Dashboard's Google provider settings. For local development, use Supabase's documented environment-backed Auth configuration with the secret in an ignored local environment file; do not commit a populated value.

## Redirects and account linking

Add only the exact application callback URLs required for each environment to Supabase Auth's redirect allow-list. Keep production and development entries distinct and remove obsolete entries. The application's requested `redirectTo` must match an allow-listed URL.

Do not automatically merge accounts because provider emails match. Account linking must be an explicit, authenticated user action, initiated from an existing session and completed by proving control of the additional identity. Preserve the current account unless the user confirms linking; never use mutable user metadata as authorization evidence. Supabase Auth's manual linking must be enabled only for environments where the application implements this explicit flow.

## Runtime configuration

The migration intentionally inserts no operational values. Populate managed values out of band in `private.product_config` through a trusted administrative path. Required key names are contractual; values are environment-managed and must be validated against the owning feature's range/type before use:

- `limits.free.active_garments` — integer
- `limits.free.daily_recommendations` — integer
- `recommendations.daily_reset_timezone` — text
- `sharing.default_ttl_days` — integer
- `sharing.renewal_days` — integer
- `sharing.upload_ttl_seconds` — integer
- `sharing.max_snapshot_bytes` — integer
- `sharing.allowed_mime_types` — text array

No values, prices, provider identifiers, secrets, or defaults are seeded by this migration. A missing, malformed, or out-of-range value is an operational configuration error, not a reason to silently apply a fallback.

The Supabase OAuth token endpoint may return any successful HTTP 2xx status; clients must test the response's success status rather than require a particular code such as 201.
