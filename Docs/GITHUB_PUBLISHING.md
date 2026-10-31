# Publish Vaultline on GitHub

Vaultline includes an MIT license and contribution guidance. A safe first workflow is to push the code to a **private repository**, test it on your Mac, and then make the repository public when you are comfortable with the contents and security review.

## 1. Create the repository

1. Sign in to GitHub and open <https://github.com/new>.
2. Repository name: `Vaultline`.
3. Description: `A Mac Keychain-backed password manager with a browser extension.`
4. Choose **Private** for the first upload. You can change it to Public after reviewing the source and completing your local test plan.
5. Do not select GitHub's options to add a README, `.gitignore`, or license; those files are already in this project.
6. Create the repository.

## 2. Prepare the local project

Extract the Vaultline 1.0.0 ZIP to a stable folder. In Terminal, change to that folder, for example:

```bash
cd ~/Downloads/Vaultline_Desktop_1.0.0
```

Check that the local extension IDs are placeholders and not personal IDs. The `.gitignore` excludes those files, local build output, backup files, exported CSVs, and common secret files.

Run validation:

```bash
chmod +x Scripts/*.sh
./Scripts/verify-static.sh
```

On a Mac, also build and test the app before sharing a release:

```bash
./Scripts/build-macos.sh
```

## 3. Initialize Git and review exactly what will be uploaded

```bash
git init -b main
git add .
git status --short
git diff --cached --stat
```

Before committing, inspect the staged file list and search for anything private:

```bash
git diff --cached
```

Do not commit passwords, card data, Keychain exports, `.vaultline` backups, plaintext CSV exports, personal extension IDs, signing certificates, private keys, tokens, `.env` files, or screenshots containing secrets. If anything sensitive appears in the staged diff, remove it from the staging area and fix `.gitignore` before continuing.

Commit:

```bash
git commit -m "Release Vaultline 1.0.0 source"
```

## 4. Connect and push to GitHub

Replace `YOUR-GITHUB-USERNAME` with your GitHub username:

```bash
git remote add origin https://github.com/YOUR-GITHUB-USERNAME/Vaultline.git
git push -u origin main
```

Use GitHub's browser sign-in / credential manager or GitHub CLI. Do not paste an access token into source files or commit messages.

## 5. Add a release after real testing

Only create a stable `v1.0.0` release after the Mac build, Keychain, native messaging, browser autofill, backup/restore, and feature test plan have passed.

```bash
git tag -a v1.0.0 -m "Vaultline 1.0.0"
git push origin v1.0.0
```

Then, on GitHub:

1. Open the repository's **Releases** page.
2. Choose **Draft a new release**.
3. Select tag `v1.0.0`.
4. Add release notes from `CHANGELOG.md`.
5. Attach the ZIP source package and any Mac build artifacts only after they have been built and tested on a Mac.
6. Publish the release when ready.

## 6. Enable community contributions safely

- Keep `main` protected: require pull requests and at least one approval before merging.
- Use Issues for bug reports and feature proposals.
- Require contributors to run `Scripts/verify-static.sh` and include test steps.
- Review every change affecting Keychain access, LocalAuthentication, encryption, Native Messaging, web permissions, password/card form handling, and backups.
- Do not accept unreviewed changes directly into a distributed password manager.
- Enable GitHub's private vulnerability reporting in **Settings → Security** before announcing a public security-reporting route. Until you enable it, ask people not to post exploit details publicly.

## 7. Before changing the repository to Public

- Read the complete staged/source tree one more time.
- Confirm `.gitignore` is excluding local data.
- Complete `RELEASE_TEST_PLAN.md` on a Mac with disposable test credentials.
- Ask an experienced security reviewer to inspect the Keychain, authentication, backup, browser permissions, and native messaging implementation.
- Confirm `LICENSE` is present and `CONTRIBUTING.md` / `SECURITY.md` accurately describe the project's current state.

A public source repository does not mean the software has been security-audited. Keep that distinction clear in the repository description and release notes.

## App icon

The macOS app uses the same artwork as `Extension/icons/icon128.png`. On macOS, `Scripts/build-macos.sh` creates a standard `.icns` icon set with `sips` and `iconutil`, installs `Vaultline.icns` into `Vaultline.app/Contents/Resources`, and sets `CFBundleIconFile` in the app's `Info.plist`. No separate icon artwork is required.

## What is and is not uploaded

The source repository contains application code and the shared icon asset. The macOS Keychain database and records stay on the user's Mac and are not part of the repository. The `.gitignore` excludes local `Build/` output, per-install extension IDs, exported CSV/backup files, and common secret/key files. Still review `git status --short` and the staged diff before pushing; never commit a vault export, real credentials, personal extension IDs, signing assets, tokens, or private keys.
