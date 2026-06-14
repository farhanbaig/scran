# Clearo Privacy Policy

**Effective date:** [SET BEFORE PUBLISHING]
**Last updated:** [SET BEFORE PUBLISHING]

Clearo ("the app") is made by **Wireside Studios Ltd**, a company registered in England and Wales ("we", "us"). We are the **data controller** for the personal data described in this policy.

- **Controller:** Wireside Studios Ltd, [REGISTERED ADDRESS], United Kingdom
- **Company number:** [COMPANY NUMBER]
- **Contact:** hello@getclearo.com
- **ICO registration:** [ICO REGISTRATION NUMBER — register and pay the data protection fee before release]

Clearo is a **wellness app**. It helps you log food and understand what's in it. It does not diagnose, treat, or prevent any condition, and it is not a medical device.

---

## 1. What we collect and why

| Data | Where it comes from | Why we process it | Lawful basis (UK GDPR Art. 6) |
|---|---|---|---|
| Account details (email address, hashed password) | You, at sign-up | Sign-in, cross-device sync, account recovery | Contract (Art. 6(1)(b)) |
| Anonymous account ID | Generated if you continue without an account | Provide the app without requiring an email | Contract |
| Profile and plan inputs (sex, date of birth, height, weight, activity level, goal) | You, during onboarding; optionally imported from Apple Health with your permission | Calculate your calorie and nutrient plan | Contract |
| **Focus areas** (e.g. heart, blood sugar) | You, during onboarding | Choose which nutrition numbers the app surfaces for you | **Explicit consent (Art. 9(2)(a))** — these can imply health information, so we treat them as special category data. You can withdraw consent by clearing them or deleting your account. |
| Food log entries (foods, portions, nutrition, time logged) | You | The core food-diary feature; sync across your devices | Contract |
| Food photos | You, when you use plate/label scanning | Estimate nutrition from the photo; show the photo in your log | Contract |
| Weight entries | You; optionally Apple Health | Progress tracking | Contract |
| Apple Health data (height, weight, age, sex, activity) | Apple Health, **only with your permission** | Pre-fill your profile and show daily activity | Consent (revocable in iOS Settings → Health) |
| Subscription status | Apple / RevenueCat | Unlock Pro features you've paid for | Contract |
| Support emails and diagnostic ID | You, if you contact us | Answer your support request | Legitimate interests |
| Usage analytics and crash reports | The app (EU-hosted PostHog / Sentry), **if enabled in a future version** | Fix bugs and improve the app | Legitimate interests; we will update this policy before enabling |
| Marketing emails | Only if you opt in at sign-up | Occasional tips and product updates | Consent — unsubscribe any time |

We do **not** sell your data, show third-party advertising, or use your data for advertising of any kind. Apple Health data is never used for marketing, advertising, or data mining, and is never shared with third parties except as needed to provide the app's features at your request.

## 2. AI processing of food photos

When you scan a plate or a nutrition label, your photo is sent to our server (Supabase, EU) and then to **Google's Gemini API** to estimate the food and its nutrition. The photo is processed to produce the estimate and is not used by us to train AI models. Google processes this data as our processor under its API terms; this involves a **transfer outside the UK** safeguarded by the UK International Data Transfer Addendum / standard contractual clauses in Google's terms.

## 3. Where your data lives

Your synced data (account, plan, food log, photos) is stored with **Supabase** in the **EU (eu-west-1, Ireland)**, protected by row-level security so only your account can read your rows. Data also lives locally on your device so the app works offline.

## 4. How long we keep it

- **Account and log data:** until you delete your account.
- **Deletion:** the app has **Settings → Delete account**, which permanently deletes your account and all synced data from our servers. Local data is removed from the device at the same time.
- **Support emails:** up to 24 months.
- **Backups:** server backups roll off automatically within [e.g. 30] days of deletion.

## 5. Your rights

Under UK GDPR you can: access your data (the app has free **CSV export** built in), correct it, delete it (in-app), restrict or object to processing, port it, and withdraw consent at any time (e.g. clear your focus areas, revoke Apple Health access, unsubscribe from emails).

To exercise any right, email **hello@getclearo.com**. We respond within one month. You can also complain to the **Information Commissioner's Office** (ico.org.uk), though we'd appreciate the chance to fix things first.

## 6. Children

Clearo is not intended for children under 16, and we do not knowingly collect their data. The App Store age rating reflects this.

## 7. Our processors

| Processor | Purpose | Location |
|---|---|---|
| Supabase | Database, auth, storage, edge functions | EU (Ireland) |
| Google (Gemini API) | AI nutrition estimation from photos | US (UK IDTA / SCC safeguards) |
| Apple | Sign in with Apple, subscriptions, App Store | Global (Apple DPA) |
| RevenueCat | Subscription management (when Pro launches) | US (SCC safeguards) |
| PostHog (EU) / Sentry | Analytics / crash reporting (only if enabled in a future version) | EU |

## 8. Security

Transport encryption (TLS) everywhere; row-level security on every table; AI provider keys held server-side only (never in the app binary); passwords hashed by our auth provider; photos stored in a private bucket scoped to your account.

## 9. Changes

If we make material changes, we'll tell you in the app before they take effect and update the dates above.
