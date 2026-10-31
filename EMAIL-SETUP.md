# The Hunt — custom registration email setup

This project keeps Supabase Auth for accounts and passwords. To avoid the tiny built-in Supabase email allowance, connect a transactional SMTP provider to Supabase Auth. The website must NOT send confirmation emails directly from the browser.

## What is already prepared
- `config.js` uses the Supabase project base URL (without `/rest/v1/`).
- Signup continues to use `supabase.auth.signUp()`, so Supabase still creates accounts and generates secure confirmation links.
- No SQL migration is needed for SMTP setup.

## One-time setup required by the project owner
1. Create an account with an SMTP email provider such as Resend.
2. Add a domain you own to that provider and complete its DNS verification (SPF/DKIM). A domain you do not control cannot be used for reliable production sending.
3. In the provider, create an SMTP credential/API key. Keep it private. Do not put it in `config.js`, Netlify frontend variables, or any browser JavaScript.
4. In Supabase Dashboard, open **Authentication → SMTP Settings** (sometimes shown under **Settings → Authentication → SMTP**). Enable custom SMTP and enter the provider's exact SMTP host, port, username, and password. For Resend, the usual values are host `smtp.resend.com`, username `resend`, and the SMTP password is the API key; use the port specified by Resend for your account (commonly 465 or 587).
5. Set the sender email to an address on the verified domain, e.g. `noreply@your-owned-domain`.
6. In Supabase **Authentication → Rate Limits**, review the email rate limit after custom SMTP is enabled. Set a limit your provider plan can actually support. It is not unlimited; provider quotas and anti-abuse limits still apply.
7. Send a test signup/confirmation email, then verify that the link returns to `https://grand-gingersnap-e80e22.netlify.app`. Keep the existing Site URL and redirect allow-list.

## Important
- Do not run or delete SQL queries for this change.
- Do not expose SMTP passwords, provider API keys, or Supabase `service_role` keys.
- A custom SMTP provider is not an email server we can create inside static Netlify files. The provider account, verified sending domain, credentials, and plan must be supplied by the owner.
- Supabase Auth still handles signup, password security, confirmation tokens, and confirmation status.
