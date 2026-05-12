# Publishing fasttext_flutter to pub.dev

## Prerequisites checklist

- [ ] **Google account** linked to [pub.dev](https://pub.dev) — sign in once with `dart pub login`
- [ ] `dart` SDK ≥ 3.3.0 in PATH
- [ ] `flutter` in PATH (needed for `flutter pub publish`)
- [ ] `pub.dev` username/publisher set up (see Step 1 if first-time)
- [ ] `dart pub publish --dry-run` passes with **0 warnings**

---

## Step 1 — One-time pub.dev account setup

```powershell
# Authenticate (opens browser, stores token)
dart pub login
```

You will be redirected to accounts.google.com. After approval, the CLI stores
a credential token in your profile. You only need to do this once per machine.

> **Optional: create a verified publisher**
> A verified publisher (`yourcomain.com`) shows a badge on pub.dev and
> increases user trust. Set it up at: https://pub.dev/publishers
> You need DNS access to your domain to verify ownership.

---

## Step 2 — Update pubspec.yaml

Before publishing, make sure these fields are correct in `pubspec.yaml`:

```yaml
name: fasttext_flutter
description: >
  On-device text classification and sentence embeddings using fastText
  .ftz quantized models via Dart FFI. Supports predict(), computeEmbedding(),
  and cosine similarity. Works on Android, iOS, macOS, Linux, and Windows.
version: 0.1.0
homepage: https://github.com/YOUR_GITHUB/fasttext_flutter    # ← update
repository: https://github.com/YOUR_GITHUB/fasttext_flutter  # ← update
issue_tracker: https://github.com/YOUR_GITHUB/fasttext_flutter/issues
```

> `homepage` and `repository` are shown prominently on pub.dev.
> Use your actual GitHub repo URL.

---

## Step 3 — Push to GitHub (recommended before publishing)

pub.dev links directly to your repository. It is best practice to publish
from a clean, tagged commit.

```powershell
cd d:\MAD\flutter\pub_dev_pkgs\fasttext_flutter

git init          # if not a git repo yet
git add .
git commit -m "chore: initial release v0.1.0"
git remote add origin https://github.com/YOUR_GITHUB/fasttext_flutter.git
git push -u origin main

# Tag the release
git tag v0.1.0
git push origin v0.1.0
```

---

## Step 4 — Final dry-run

Always run the dry-run immediately before publishing to catch last-minute issues.

```powershell
cd d:\MAD\flutter\pub_dev_pkgs\fasttext_flutter
dart pub publish --dry-run
```

Expected output:
```
Package has 0 warnings.
```

If there are warnings, fix them before proceeding. Common issues:

| Warning | Fix |
|---|---|
| `homepage` missing / invalid | Add a valid URL to `pubspec.yaml` |
| No LICENSE file | Ensure `LICENSE` exists in the root |
| `CHANGELOG.md` format | First heading must be `## <version>` |
| Large files included | Add them to `.pubignore` |

---

## Step 5 — Exclude unnecessary files

Create a `.pubignore` file (same syntax as `.gitignore`) to exclude
files that shouldn't be uploaded to pub.dev:

```
# Development artifacts
*.ipynb
fastextmodel_test.ipynb
model.ftz
*.ftz
*.bin
plan.md
tasks.md
.vscode/
.idea/

# CI / tooling
.github/
```

> The `model.ftz` must be excluded — it is a 1+ MB binary that would bloat
> the pub.dev package. Users supply their own models.

Re-run `dart pub publish --dry-run` after creating `.pubignore` to confirm
the package size is reasonable (ideally < 2 MB without models).

---

## Step 6 — Publish 🚀

```powershell
dart pub publish
```

You will be shown the list of files to be uploaded and asked to confirm.
Type `y` and press Enter.

```
Publishing fasttext_flutter 0.1.0 to https://pub.dev.
|> Do you want to publish fasttext_flutter 0.1.0 (y/N)? y
```

pub.dev usually processes the package within **30 seconds to 2 minutes**.
The package will appear at: `https://pub.dev/packages/fasttext_flutter`

---

## Step 7 — After publishing

### Verify the page looks correct

- Check the **Readme** tab renders properly
- Check the **Changelog** tab shows the correct version
- Check the **Example** tab links to `example/lib/main.dart`
- Check the **API docs** tab — all public symbols should be documented

### Claim a pub.dev score

pub.dev automatically scores packages (0–160 pts). To maximize it:

| Check | Action |
|---|---|
| **Dart formatting** | Already done — `dart format` ✅ |
| **Static analysis** | Already done — `dart analyze` ✅ |
| **Documentation** | Every public member has a doc comment ✅ |
| **`pubspec.yaml` metadata** | Add `topics:` and `screenshots:` |
| **Supported platforms** | Our build hooks cover all 5 ✅ |
| **LICENSE file** | Present ✅ |

### Add topics in pubspec.yaml

```yaml
topics:
  - nlp
  - machine-learning
  - text-classification
  - embeddings
  - ffi
```

---

## Releasing future versions

1. Bump the version in `pubspec.yaml` (follow [semver](https://semver.org))
2. Add a new entry to the **top** of `CHANGELOG.md`:
   ```md
   ## 0.2.0
   - Added xyz feature.
   - Fixed abc bug.
   ```
3. Commit, tag, push.
4. Run `dart pub publish --dry-run` → `dart pub publish`.

---

## Quick reference

```powershell
# Authenticate (once)
dart pub login

# Validate
dart pub publish --dry-run

# Publish
dart pub publish

# Check your packages
# https://pub.dev/publishers / https://pub.dev/my-packages
```
