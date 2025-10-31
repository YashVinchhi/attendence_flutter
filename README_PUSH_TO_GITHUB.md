# How to push this project to a new GitHub repository and enable CI/CD

This project is a Flutter app located in this workspace. Follow these steps to create a new GitHub repository under your account, push the code, and enable the GitHub Actions workflow that builds Android artifacts on pushes to `main`.

Replace <YOUR_GITHUB_USERNAME> and <YOUR_REPO> in the examples below with your actual GitHub username and repository name.

This repository and CI configuration are maintained by Yash VInchhi (https://github.com/YashVinchhi).

1. Create a new repository on GitHub (if you haven't already)
   - Go to https://github.com/YashVinchhi
   - Click "New" and create a repository named `attendence_flutter`.
   - Do not initialize with README/Licenses (we'll push the local repo).

2. Initialize local git and push
```bash
cd "C:/Users/Admin/Downloads/attendence_flutter"
# Initialize git (if not already)
git init
git add .
git commit -m "Initial commit: attendance_flutter app"
# Add your remote (use HTTPS or SSH depending on your setup).
# HTTPS (recommended if you plan to use a Personal Access Token):
git remote add origin https://github.com/YashVinchhi/attendence_flutter.git
# or SSH (if you've set up SSH keys):
# git remote add origin git@github.com:<YOUR_GITHUB_USERNAME>/<YOUR_REPO>.git
# Push to main (create main branch if needed)
git branch -M main
git push -u origin main
```

3. Enable GitHub Actions workflow
- The repository contains `.github/workflows/android_build.yml` which runs on pushes to `main` and builds an AAB.
- After pushing, go to Actions tab to view builds.

4. Optional: Publish to Google Play from the workflow
- To auto-publish, add the following secrets to the GitHub repository (Settings → Secrets → Actions):
  - `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`: full JSON contents of the Google Play service account key.
  - `PACKAGE_NAME`: Android package name (e.g., `com.example.myapp`).
- The workflow will publish to the `internal` track using `upload-google-play` action.

5. Notes
- The workflow expects Flutter SDK; it uses `subosito/flutter-action` to install Flutter on the runner.
- The action uploads the built AAB as an artifact named `app-aab`.

## Downloading the latest APK/AAB

After each successful push to `main`, the GitHub Actions workflow builds the APK and AAB and creates a GitHub Release with those artifacts attached. You (or other users) can download the latest release artifacts directly from the repository releases page or via a stable URL:

- Latest APK:

```
https://github.com/YashVinchhi/attendence_flutter/releases/latest/download/app-release.apk
```

- Latest AAB:

```
https://github.com/YashVinchhi/attendence_flutter/releases/latest/download/app-release.aab
```

If the file is not present in the release yet (workflow failed or assets not uploaded), the link will return a 404.

If you want, I can create a GitHub remote and push automatically from this environment — but I cannot access your GitHub account or create repos without your credentials or a personal access token. For security, do not paste tokens here; instead run the commands locally or use the `gh` CLI or GitHub Desktop.

Repository URL (this project): https://github.com/YashVinchhi/attendence_flutter

If you run into problems pushing or the Actions workflow doesn't trigger, see the troubleshooting section below.

---

## Troubleshooting: CI didn't start after push

If the GitHub Actions workflow did not start after you pushed to `main`, try these checks:

1. Verify the workflow file landed on `main`:

```bash
git checkout main
git pull origin main
git ls-tree -r main --name-only | findstr .github\workflows\android_build.yml
```

2. Manually trigger the workflow from the Actions tab by enabling the `Workflow_dispatch` trigger (the workflow in this repo now supports manual dispatch). Open your repo → Actions → select the workflow → "Run workflow" → choose branch `main`.

3. Confirm the workflow YAML is valid: open the workflow file at `.github/workflows/android_build.yml` in the GitHub UI. If there's a YAML syntax problem, GitHub shows an error in Actions when trying to run.

4. Check logs & permissions: if the workflow fails immediately, open the run and read startup logs. Common causes include missing `GITHUB_TOKEN` (automatically provided for public repos) or runner configuration.

5. If you get a 404 when visiting download links, the workflow likely failed before attaching assets; open Actions → latest run → logs to see build errors.

If you want me to, I can:
- walk you through verifying that the workflow file is present on `main` and run it manually, or
- add more logging/steps to the workflow to help debug build failures.
