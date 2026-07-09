# RULES.md — BarNote Admin (iOS)

> Read this before touching code. It captures structure, contracts, and gotchas so a new AI session can work safely without re-reading the whole project.

## Project Overview
- **BarNote Admin**: Korean-language iOS SwiftUI admin app for the "BarNote" (바노트) barcode taste-note service. Personal-device install only, never App Store.
- Mobile port of the admin web app (`../barcode-taste-note-admin`); calls the **production** API `https://api.barnote.net` directly — there is NO staging environment.
- Tech: SwiftUI + Observation framework, async/await, Auth0.swift (SPM), hand-rolled EAN barcode encoder + CoreImage Code128 fallback.

## Tech Stack & Build
- Xcode **26+** (iOS 26 SDK); `IPHONEOS_DEPLOYMENT_TARGET = 26.0`, Swift 5.0 mode. Open with `open BarNoteAdmin.xcodeproj`.
- Bundle id `com.oq.barnote.admin`; iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), **portrait-only**. Team `Z97K7ZHNKX`, automatic signing.
- Single SPM dependency: **Auth0.swift pinned exactVersion 2.16.1** (bump requires editing the pbxproj requirement). Pulls SimpleKeychain + JWTDecode transitively.
- **Folder-synchronized project** (objectVersion 77): files created under `BarNoteAdmin/` on disk are picked up automatically — NEVER hand-edit pbxproj to add sources.
- **No physical Info.plist**: `GENERATE_INFOPLIST_FILE = YES`; all keys live as `INFOPLIST_KEY_*` build settings (display name "BarNote Admin", Korean `NSPhotoLibraryUsageDescription`, portrait orientation). No custom URL schemes, no ATS exceptions — Auth0 callback works via ASWebAuthenticationSession without a scheme.
- Shared scheme `BarNoteAdmin` lives at `BarNoteAdmin.xcodeproj/xcshareddata/xcschemes/BarNoteAdmin.xcscheme` — this is what makes CLI `xcodebuild -scheme BarNoteAdmin` work; don't de-share/delete it.
- Git: only a 1-line README was ever committed (57d4d99); the entire app tree is currently **untracked** — history is no safety net. `Auth0.plist` is deliberately not gitignored (Domain/ClientId are not secrets here).

## Directory Structure
```
BarNoteAdmin.xcodeproj/          # objectVersion 77, folder-synced; shared scheme in xcshareddata/
BarNoteAdmin/
  BarNoteAdminApp.swift          # @main + RootView (auth-state switch)
  Auth0.plist                    # Auth0 Domain + ClientId
  Assets.xcassets/               # AppIcon + AccentColor (referenced by ASSETCATALOG_* build settings — don't rename)
  Core/
    Constants.swift              # enum C (URLs, pagingCount=20) + ProductTypeLabel/ProductStyleLabel/GrapeVarietyLabel (Korean label tables)
    Models.swift                 # Codable models mirroring admin web src/types/api.ts + APIEnvelope + DateLabel
    AuthManager.swift            # @MainActor @Observable Auth0 singleton (port of main app's AuthStore)
    AdminAPI.swift               # static API client mirroring admin web src/api/admin.ts + AdminAPIError
    BarcodeRenderer.swift        # EAN-13/UPC-A/EAN-8 encoder, Code128 fallback, BarcodeSymbolView
  Views/
    MainTabView.swift            # 5-tab root + ManageView (tools + logout)
    LoginView.swift              # Google login screen
    DashboardView.swift          # stat card grid (대시보드)
    ProductsView.swift           # search + infinite scroll (제품)
    ProductDetailView.swift      # edit form, images, barcodes, auto-fill, merge, delete
    NotesView.swift              # read-only notes + NoteDetailSheet (노트)
    ReportsView.swift            # reports + ReportDetailSheet (신고)
    BarcodeScansView.swift       # scan-success stats + BarcodeProductSheet
    BarcodeFailuresView.swift    # failed barcodes, per-row delete
    DeletedImagesView.swift      # unreferenced images grid + Delete All
    Components.swift             # errorAlert/toast modifiers, RemoteImage, StatCard, TagView, RatingLabel, ImagePagerView, sheet-item wrappers
```

## Architecture & Data Flow
- **No view models.** Every screen is a SwiftUI struct with local `@State` only; views call `AdminAPI` static methods directly (async/await). No ObservableObject / @Published / Combine anywhere.
- `AuthManager` is a `@MainActor @Observable final class` singleton (`AuthManager.shared`), held in views as a plain `let` — re-rendering works ONLY because of the Observation framework. Do not convert to ObservableObject (silently breaks RootView/LoginView/ManageView). States: `.checking → .loggedOut / .loggedIn`.
- `RootView` (BarNoteAdminApp.swift) switches on auth state: `.checking` → ProgressView, `.loggedOut` → LoginView, `.loggedIn` → MainTabView; runs `auth.bootstrap()` in `.task` guarded by `state == .checking`.
- Detail screens that mutate data receive a `() -> Void` callback (`onProductChanged` / `onReplied`) and call it after mutations so parent lists reload.
- **Cross-repo parity is the contract**: Core mirrors the admin web (`src/api/admin.ts`, `src/types/api.ts`, PRODUCT_STYLE_GROUPS, GRAPE_VARIETY_GROUPS, jsbarcode policy); AuthManager/multipart mirror the main iOS app `iOSBarcodeTasteNote` (AuthStore, NetworkClient.upload). Doc comments state this ("웹과 동일", "본가 앱과 동일") — check parity before changing any mirrored code.
- **For actual payload shapes, trust the main iOS app's models over the web's `types/api.ts`**: TS interfaces are not validated at runtime and declare fields the server never sends (e.g. `id` on ProductInfo/NoteInfo — the main app computes `id` from `product.id`/`note.id`). When a decode fails, compare against `iOSBarcodeTasteNote/Projects/App/Sources/Domain/Models/` first. (Main app's decoder uses convertFromSnakeCase; this app uses explicit CodingKeys — same wire format.)

## Auth (Auth0)
- Tenant/client shared with the main consumer app; config in `Auth0.plist` (Domain/ClientId). Missing Domain → `fatalError` at startup.
- Login: connection hardcoded to `google-oauth2`, audience `https://barnote.net/` (**trailing slash matters**), scope `openid profile offline_access` — `offline_access` yields the refresh token the whole renewal scheme depends on; never drop it.
- Callback URL **reuses the MAIN app's bundle id**: `com.oq.barnote://<domain>/ios/com.oq.barnote/callback` (`C.mainAppBundleId`) so no Auth0 dashboard change is needed. Do NOT "fix" it to `com.oq.barnote.admin`.
- Tokens live in Auth0 `CredentialsManager` (keychain via SimpleKeychain). All access goes through `credentials(minTTL: 60)` → auto-renews when <60s validity remains. `bootstrap()` gates on `hasValid(minTTL: 60) || canRenew()`.
- Two credential-wipe paths: (1) HTTP 401 from the server → `handleUnauthorized()`; (2) `accessToken()` itself wipes on a non-transient refresh failure. Transient (network-ish) refresh errors throw `TokenError.transient` and keep the session — the `isNetworkError` string heuristic is deliberately copied from the main app.
- `bootstrap()` treats an offline cold start as `.loggedIn` (keeps credentials; API calls surface the network error) — intentional.
- `logout()` / `handleUnauthorized()` clear local credentials only; the Auth0 web session is kept on purpose (skips account picker on re-login).

## Backend API (Core/AdminAPI.swift)
- Base: `C.apiBaseURL = https://api.barnote.net` (hardcoded, production only). Images: `C.imageURL(id)` = `https://barnote.net/images/<id>`; `C.deletedImageURL(id)` = `https://barnote.net/deleted/images/<id>`. Dedicated URLSession with 30s request timeout.
- Every request first awaits `AuthManager.shared.accessToken()` (Bearer header). Token failure short-circuits — **never send unauthenticated requests** (prevents 401 → credential-wipe cascade). Transient token errors → `.network`; others → `.unauthorized`.
- Response envelope `{ result: Bool, data: T?, error: Int? }`. Check order in `request()` is load-bearing: 401 → error-envelope (runs even on 2xx) → non-2xx `.status`. `decode<T>` tries `APIEnvelope<T>` first, then bare `T` (a payload type with its own `result`/`data`/`error` fields would be mis-unwrapped).
- `AdminAPIError`: `.unauthorized`, `.server(Int)` (codes 100–108, Korean messages matching web `getErrorMessage`), `.status(Int)`, `.network`, `.decoding(endpoint:detail:)` — decoding failures carry the endpoint + failing field path (e.g. `data.product.rating 타입 불일치`) and show them in the alert (admin-only app, detail is intentional).
- All API failures are logged via `os.Logger` (subsystem = bundle id, category `AdminAPI`): network/401/server-code/HTTP-status one-liners, and full decode diagnostics (both envelope and bare decode attempts + response-body snippet). `decode()` keeps the envelope-attempt error and reports whichever error has the deeper codingPath — don't revert it to a silent `try?`.
- Paging: 1-based `page`, `per = C.pagingCount = 20`.

| Method | Path | Body/Query | Returns |
|---|---|---|---|
| GET | `admin/dashboard` | – | DashboardStats |
| GET | `admin/report` | – | [Report] |
| PUT | `admin/report` | {id, reply} | – |
| GET | `products` | page, per, order_by=registered[, name] | [ProductInfo] |
| GET | `products/:id` | – | ProductInfo |
| GET | `admin/product/details` | product_name, only_details("true"/"false") | ProductDetailsResponse |
| GET | `admin/product/main_image` | product_id | ProductMainImageResponse |
| PUT | `admin/product` | UpdateProductRequest | Product |
| POST | `admin/product/merge` | {product_id, to_product_id} | – |
| DELETE | `admin/products/:product_id` | – | – |
| GET | `admin/product/barcodes` | product_id | [String] |
| POST/PUT | `admin/barcode` | {barcode_id, product_id} | – |
| DELETE | `admin/barcode/:barcode_id` | – | – |
| GET | `admin/notes` | page, per | [NoteInfo] |
| GET | `users/:id` | – | UserDetailResponse |
| GET | `images` | page, per[, product_id][, note_id] | [String] |
| POST | `admin/image` | multipart: image_id + file "image" (replace) | – |
| POST | `admin/image/url` | {add_image_url, image_id?, product_id?} | – |
| POST | `images/` **(trailing slash required)** | multipart: id=UUID[, product_id][, note_id] + file "image" | – |
| DELETE | `admin/images/:id` | – | – |
| GET | `admin/deleted/images` | – | [String] |
| DELETE | `admin/deleted/images` | – | – |
| GET | `admin/barcode/failures` | – | [String: BarcodeFailure] |
| DELETE | `admin/barcode/failures/:barcode_id` | – | – |
| GET | `admin/barcode/successes` | – | [String: BarcodeSuccess] |
| GET | `products/barcode/:barcode_id` | – | ProductByBarcodeResponse |

- Multipart: file part always named `image`, filename `image.jpg`, default mime `image/jpeg`, boundary `Boundary-<UUID>` (matches main app's NetworkClient.upload).

## Data Models (Core/Models.swift)
| Type | Key fields (JSON key if snake_case) |
|---|---|
| Product | id, name, type: Int, desc, rating: Double?, flavorInfos (flavor_infos), details, registered, noteCount (note_count) |
| ProductDetails | style/grape: Int?, manufacturer/country: String?, alcohol/ibu: Double? — no CodingKeys |
| ProductInfo | product, imageIds (image_ids), favoriteCount (favorite_count); `id` is COMPUTED = product.id — server sends no top-level id |
| Report | id, productId, userId, body, state, reply (var), type, registered; computed typeLabel (0=제품 신고, 1=기타), isReplied |
| DashboardStats | 14 optional Int counters, all snake_case mapped |
| UpdateProductRequest | Encodable only; productId (product_id), name?, desc?, type?, details? |
| User / UserDetailResponse | nickName (nick_name), intro, imageId; noteCount, followerCount |
| PublicScope | Int enum 0/1/2, custom init falls back to .private on unknown values; label + systemImage |
| Note / NoteInfo | note, product, imageIds, productImageId (product_image_id), flavors, user?; NoteInfo `id` is COMPUTED = note.id |
| BarcodeFailure/Success | updatedAt (updated_at), failCount/successCount; non-Codable Row wrappers flatten dict key → barcodeId |
| ProductByBarcodeResponse | product, imageIds, favoriteCount |

- **Explicit CodingKeys on every model**; JSONDecoder/Encoder use the DEFAULT key strategy — never rely on convertFromSnakeCase.
- Dates stay raw `String`; display only via `DateLabel.display(_:)` → "yyyy. MM. dd. HH:mm" (ko_KR), with a microseconds fallback formatter for Postgres 6-digit fractional seconds.
- Non-id fields are optional-heavy to tolerate partial payloads; unknown enum ints get label fallbacks (`기타(<n>)`, `알 수 없음(<n>)`).

## Screens & Navigation
| Screen | Entry | Notes |
|---|---|---|
| MainTabView | root when logged in | 5 tabs, each in its own NavigationStack: 대시보드/제품/노트/신고/관리 |
| DashboardView | 대시보드 tab | StatCard grid; daily revenue estimate = `floor(2000/30 × premiumUserCount)` won (web parity, hardcoded) |
| ProductsView | 제품 tab | searchable, infinite scroll, `NavigationLink(value:)` + `navigationDestination(for: ProductInfo.self)` |
| ProductDetailView | push from ProductsView | edit form, image upload/URL, barcodes, auto-fill, merge (sleeps 1s before dismiss), delete. List payload omits desc/details (abridged product), so it re-fetches `products/:id` on appear and fills the form via `applyInfo` (web-dialog parity) |
| NotesView | 노트 tab | read-only, infinite scroll, `sheet(item:)` → NoteDetailSheet |
| ReportsView | 신고 tab | non-paged `getReports()`; ReportDetailSheet posts reply; type==1 (기타) has NO product |
| ManageView | 관리 tab | sole entry to DeletedImagesView / BarcodeFailuresView / BarcodeScansView; logout behind confirmationDialog |
| LoginView | when loggedOut | "Google로 로그인"; errors via manual Binding onto `auth.loginErrorMessage` |

- Infinite-scroll pattern (Products/Notes): `hasMore = result.count == C.pagingCount`, last-row `.onAppear` → loadNextPage, id-dedup on append, and a **`loadGeneration` int token** guards every post-await state mutation (reload increments it; stale tasks bail out). Keep this when touching list loads.
- Modals via `sheet(item:)` / `fullScreenCover(item:)` with tiny Identifiable wrappers (`BarcodeSheetItem`, `ImageViewerState`); barcode sheets use `.presentationDetents([.medium])`.

## Coding Conventions
- All user-facing strings, comments, and doc comments are in **Korean**; error wording matches the admin web `getErrorMessage`.
- Caseless enums as namespaces for stateless utilities: `AdminAPI`, `C`, `DateLabel`, `BarcodeEncoder`, label tables. Typed error enums, not string errors.
- Error UI: do/catch → `errorMessage = error.localizedDescription` → shared `.errorAlert($errorMessage)`; success feedback → `.toast($toastMessage)` (auto-dismiss ~2s).
- Initial load: `.task { if <empty> { await load() } }` + `.refreshable`; user actions wrapped in `Task { await ... }`; loading flags reset via `defer`; tolerant parallel fetches use `async let x = try? ...`.
- All remote images through `RemoteImage` (AsyncImage wrapper); URLs built only via `C.imageURL` / `C.deletedImageURL`.
- Ratings: server scale 0–10, **always displayed ÷2** ("%.1f", 5-star scale) via `RatingLabel` — this is web parity, do not "fix".
- `// MARK: -` comments partition files by section; IDs/barcodes render monospaced with `.textSelection(.enabled)`.

## Critical Rules & Gotchas
- **This app operates on production data.** Delete product, merge, barcode deletes, and Delete All images are irreversible. When testing, avoid exercising destructive actions.
- **URL building**: `AdminAPI.request` concatenates strings (`C.apiBaseURL.absoluteString + "/" + path`) specifically to preserve trailing slashes — `POST images/` breaks with `appendingPathComponent`. Query `+` is manually re-encoded to `%2B` (server reads literal `+` as space).
- Keep the `request()` check ordering (401 → envelope → status) and the never-send-without-token rule intact.
- Auth0 invariants: callback URL uses the main app's bundle id, connection `google-oauth2` only, audience has a trailing slash, scope includes `offline_access`. Changing any of these breaks login or refresh.
- Barcode scan/failure lists sort by raw `updatedAt` string comparison — assumes server's sortable timestamp format.
- Image handling in ProductDetailView is stateful: main image exists → replace by `imageId`; else create by `productId`; `updateImageUrl` gets exactly one of the two. Cache busting appends `?v=<imageVersion>` after mutations (v==0 uses the plain URL to keep normal caching).
- ProductDetailView's type Picker appends a synthetic `기타(N)` entry for unknown type ints so saving doesn't clobber legacy values; the type table has gaps (0,1,2,3,4,7 — no 5/6). Style/grape codes are banded ints synced with web constants.
- Report `type == 1` (기타) has no product — never call `getProductDetail` for it.
- BarcodeSymbolView draws bars in fixed `Color.black` on a fixed white card (`Color.primary` would vanish in dark mode); Code128 images need `.interpolation(.none)`. Checksum-invalid numeric strings fall back to Code128 (jsbarcode parity); UPC-A = EAN-13 with a leading 0.
- Deletion behaviors intentionally differ: BarcodeFailuresView removes the row locally without refetch; DeletedImagesView refetches after Delete All (both mirror the web).
- `ForEach(..., id: \.element)` over image-id arrays means duplicate ids would break SwiftUI identity. Keep `ProductInfo` Hashable+Identifiable and `NoteInfo`/`Report`/Row types Identifiable.

## How to Verify Changes
- Build: `xcodebuild -project BarNoteAdmin.xcodeproj -scheme BarNoteAdmin -destination 'generic/platform=iOS Simulator' build`. First build resolves SPM (Auth0 2.16.1 + SimpleKeychain + JWTDecode).
- **No test target exists** — verification is build + manual run in Simulator/device. Login requires the real Auth0 tenant, and all API calls hit production.
- Adding files: just create them on disk under `BarNoteAdmin/` (folder-synced project). Do not edit pbxproj for sources.
- When changing API/model/label/barcode code, check parity with the admin web (`src/api/admin.ts`, `src/types/api.ts`) and the main iOS app (`iOSBarcodeTasteNote`) — mirroring is the stated contract in doc comments.
