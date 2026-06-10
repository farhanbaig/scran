# Scran — the UK calorie tracker that shows its working

*Wireside Studios Ltd · iOS 17+ · SwiftUI · SwiftData · Supabase*

**Every number has a source. Every plan shows its maths.**

Scran is built directly against the four evidenced failure modes of Cal AI and
its clones: opaque plan maths, US-centric data, oversold plate-guessing, and
trust failures. Three product laws are enforced in every screen:

1. **Source badges everywhere** — every entry shows `VERIFIED LABEL`, `DATABASE`, or `ESTIMATE n%`.
2. **Show the maths** — the plan screen renders the BMR → activity → deficit → target equation in plain English.
3. **No silent failures** — every scan visibly succeeds or fails with a retry; every paywall shows the price before commitment; entitlements degrade gracefully offline.

---

## What's in this repository

```
scran/                     SwiftUI app (file-system-synchronized — new files auto-included)
  Config/                  ScranConfig: Supabase keys, product IDs, pricing copy
  DesignSystem/            "Confident Dark" tokens, fonts, SourceBadge, EquationBlock, components
  Models/                  SwiftData models, NutrientBlock, enums, PlanCalculator
  Services/                Supabase client, edge-fn clients, sync queue, entitlements/analytics/crash protocols
  Stores/                  AppModel (root @Observable)
  Features/                Onboarding · Plan · Today · Log · Scan · Entry · SavedMeals · Settings · Paywall
  Resources/Fonts/         Drop the OFL .ttf files here (see Fonts/README.md)
scranTests/                Plan calculator + portion-recompute unit tests (Swift Testing)
supabase/                  Canonical backend source: migrations + edge functions
```

The 10 screens + paywall from the build spec are all implemented:
Onboarding (4 steps) → **Plan Reveal** → Today → Log sheet → Barcode scanner →
Label camera → Plate camera → Entry Editor → Saved Meals → Settings, plus the
contextual Paywall.

---

## Backend (already provisioned)

The Supabase project **Scran** (`qrbwqvpcskwrgmzxehpt`, eu-west-1) is live with:

- **Tables** `profiles`, `plans`, `food_entries`, `saved_meals`, `weight_entries`, `ai_scan_events` — RLS on every table (`auth.uid() = user_id`).
- **Storage** private bucket `food-photos` with owner-only policies.
- **Edge Functions** `scan-label`, `scan-plate`, `lookup-barcode`, `explain-plan`, `delete-account` — all deployed and `ACTIVE`, all `verify_jwt`.
- **RPC** `ai_scans_used_today()` for the calm scan counter.

Source of truth for all of this lives in `supabase/` so you can redeploy via the
Supabase CLI.

### Required Edge Function secrets

Set these in **Supabase Dashboard → Project Settings → Edge Functions → Secrets**
(or `supabase secrets set`). `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are
injected automatically.

| Secret | Used by | Notes |
|---|---|---|
| `GEMINI_API_KEY` | scan-label, scan-plate | Google AI Studio key. Vision OCR + plate estimation. |
| `GEMINI_MODEL` / `GEMINI_MODEL_PRO` | scan-label, scan-plate | Optional. Default `gemini-flash-latest`. Pro lane can use a higher tier. |
| `ANTHROPIC_API_KEY` | explain-plan | Claude Haiku for the plan explanation. Falls back to deterministic copy if unset. |
| `ANTHROPIC_MODEL` | explain-plan | Optional. Default `claude-haiku-4-5-20251001`. |
| `REVENUECAT_SECRET_KEY` | scan-label, scan-plate | Optional. When set, Pro users (RevenueCat `pro` entitlement, keyed by Supabase user id) bypass the free scan quota. Without it everyone is treated as free tier. |

**No AI/provider keys are ever in the app binary.** The app talks only to
Supabase (publishable key + RLS) and, once wired, RevenueCat (public SDK key).

### Anonymous auth

Enable **Authentication → Sign-in providers → Anonymous** in the dashboard. The
app signs in anonymously on first launch and persists the refresh token in the
Keychain.

---

## Running the app

1. Open `scran.xcodeproj` in Xcode 26+.
2. **Fonts:** drop the seven OFL `.ttf` files into `scran/Resources/Fonts/` (see that folder's README). The app registers them at runtime; without them it falls back to system fonts and still runs.
3. Build & run on a device (camera features need real hardware; the simulator handles everything else).
4. First launch → onboard → see your transparent plan. Camera/quota features call the live Edge Functions.

Signing: the project uses automatic signing with team `L3779VFYN8`, bundle id
`com.wiresidestudios.scran`. Adjust for your account.

---

## Third-party SDKs (locked stack — wired behind protocols)

To keep the project building out of the box, RevenueCat, PostHog and Sentry are
abstracted behind protocols with safe local/console default implementations
(`Services/Entitlements.swift`, `Analytics.swift`, `CrashReporter.swift`). The
app is fully functional on these defaults — the only thing they can't do is
transact real purchases or ship telemetry.

To go live with the real stack:

1. **Add the SPM packages** in Xcode: RevenueCat, PostHog (EU), Sentry.
2. Uncomment the adapter template at the bottom of each service file.
3. Set the public keys in `ScranConfig` (`revenueCatPublicKey`, `posthogKey`, `sentryDSN`).
4. In `scranApp.init()`, swap the default implementations for the SDK-backed adapters and call their `bootstrap()`.

RevenueCat products: `scran_pro_monthly_399`, `scran_pro_annual_2499`, offering
`default`, entitlement `pro`. Configure RevenueCat to use the **Supabase user id
as the app user id** so the server-side quota check can read entitlements.

---

## Tests

`scranTests` (Swift Testing) covers the maths that must never be wrong:

- `PlanCalculatorTests` — Mifflin-St Jeor BMR, activity multipliers, 7700 kcal/kg deficit, safe-floor clamping, macro consistency, honest timeline.
- `PortionRecomputeTests` — the headline acceptance criterion: changing serving size or quantity recomputes every nutrient, always.

Run with `⌘U` or `xcodebuild test`.

---

## Acceptance criteria status

| Criterion | Status |
|---|---|
| Changing serving/quantity recomputes every nutrient everywhere | ✅ `NutrientBlock.scaled` + live editor; covered by tests |
| Airplane mode: scanning disabled w/ clear messaging; manual + saved work; syncs later | ✅ `NetworkMonitor`, LogSheet gating, offline sync queue |
| Kill network mid-purchase: no lockout, restore works | ✅ Offline entitlement cache + grace period in `LocalEntitlements`; RevenueCat grace on when wired |
| Every entry displays exactly one source badge | ✅ `SourceBadge` on every row/detail/evidence bar |
| Plan Reveal renders the equation + exercise sentence | ✅ `EquationBlock` + verbatim exercise sentence (also enforced server-side) |
| No AI provider key extractable from the IPA | ✅ All AI calls server-side in Edge Functions |
| 3 free AI scans/day enforced server-side; 4th → paywall; barcode still works | ✅ `ai_scan_events` + Edge Function 402 → contextual paywall |
| TestFlight build installable | ⏳ Archive + upload in Xcode (signing required) |

---

## Notes & known trade-offs

- **Swift language mode:** ships in Swift 5 mode with MainActor-by-default isolation (as the Xcode template was created). The code is written concurrency-clean; enabling full Swift 6 strict-concurrency will surface a few warnings in `Features/Scan/CameraInfrastructure.swift` (AVFoundation session work crosses isolation) to tidy up.
- **Region:** the existing project is eu-west-1 (spec said eu-west-2). Data residency is still UK/EU.
- **Fonts** can't be committed here (binary); add them per `scran/Resources/Fonts/README.md`.
- The `ai_scans_used_today` RPC is intentionally `SECURITY DEFINER` and callable by authenticated/anon — it only ever counts the caller's own rows.
