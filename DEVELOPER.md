# Developer Guide — fed2-tools

This guide covers everything a contributor needs to know: local testing workflow,
release promotion, GitHub Actions behaviour, and MPR submission.

---

## Quick Reference

| Task | Command |
|---|---|
| One-time local profile setup | `./setup-dev-profile.ps1 -Username <name>` |
| Build + deploy to Mudlet | `./build.ps1` |
| Build with explicit version | `./build.ps1 -Version 1.2.0` |
| Immediate reload in Mudlet | type `f2t reload` in-game |
| Test fresh-install path | type `f2t reload fresh` in-game |
| Test update dialog UI | call `f2t_trigger_update_dialog("1.0.0","9.9.9")` in Lua console |
| Promote to production (local) | `git tag -a v1.2.0 -m "Release notes"` then `git push origin v1.2.0` |
| Promote to production (GitHub UI) | Actions → "Build Package" → Run workflow → enter version |

---

## Local Dev Setup (one-time per machine)

### 1. Run the profile setup script

```powershell
./setup-dev-profile.ps1 -Username yourcharactername
```

This creates a `fed2-dev` Mudlet profile with the Fed2 host/port/login pre-filled
so you never type them again. Works on Windows, Linux, and macOS (requires
PowerShell / pwsh).

Pass `-ProfileName` to use a different name (useful if you test multiple characters):

```powershell
./setup-dev-profile.ps1 -ProfileName jane-dev -Username jane
```

Pass `-MudletConfigPath` if auto-detection fails (run Mudlet at least once first):

```powershell
./setup-dev-profile.ps1 -MudletConfigPath /home/you/.config/mudlet -Username yourname
```

### 2. First-time package install (once only)

1. Open Mudlet
2. Select the `fed2-dev` profile
3. Enter your password (saved by Mudlet after this — never asked again)
4. Connect to the game
5. **Toolbox → Package Manager → Install from file** and select:  
   `~/.config/mudlet/profiles/fed2-dev/fed2-tools.mpackage`

After this initial install, you never use the GUI install flow again.

---

## Ongoing Dev Workflow

```powershell
# Edit code, then:
./build.ps1
```

This builds the package and deploys it directly into your Mudlet profile directory.
Within **~30 seconds**, a timer inside the running package detects the new build and
automatically performs `uninstallPackage` + `installPackage` for a clean reload.

For an **immediate** reload without waiting for the timer:

```
f2t reload
```

This also does uninstall + install, so UI state is fully torn down and rebuilt.

---

## Testing Modes

### Upgrade path (default)

```
f2t reload
```

Simulates an existing user upgrading. Settings are preserved on disk before the
reinstall and reloaded by the new package's `sysInstall` handler.
Use this for most testing — it mirrors what `mpkg.upgrade("fed2-tools")` does.

### Fresh install path

```
f2t reload fresh
```

Clears the `first_run_complete` flag before reinstalling. The welcome dialog
fires, the initial mapper config is applied, and all first-run logic runs.
Use this when testing onboarding UX or any code guarded by `first_run_complete`.

### Update dialog UI

The update dialog is testable without actually upgrading. In Mudlet's Lua console:

```lua
F2T_CHANGELOG = {{version="9.9.9", body="- New feature\n- Bug fix"}}
ui_update_show_dialog("1.0.0", "9.9.9")
```

Or trigger the full download-changelog-then-show flow with a fake version gap:

```lua
f2t_trigger_update_dialog("0.0.0", "9.9.9")
```

### Old → new upgrade

To test upgrading from a specific earlier production release:

1. Install that version from MPR: `mpkg install fed2-tools` (after `mpkg update`)
2. Run `./build.ps1`
3. In Mudlet: `f2t reload`

This exercises the exact `sysInstall` upgrade path a real user would experience.

### What you cannot test locally

`mpkg.upgrade()` downloads from the Mudlet Package Repository CDN. That delivery
mechanism is Mudlet's own code — you don't need to test it. Every meaningful line
in the post-install handlers runs identically whether triggered by `mpkg.upgrade()`
or by `installPackage()` directly.

---

## Build Script

```powershell
./build.ps1                   # Dev build, deploys to fed2-dev profile
./build.ps1 -Version 1.2.3    # Simulate a specific version (suppresses update popup)
./build.ps1 -Profile other    # Deploy to a different profile name
```

Output is always `build/fed2-tools.mpackage`. The `-Profile` flag also writes a
`fed2-tools-rebuild.stamp` file to the profile directory — this is what the
in-game auto-reload timer watches.

---

## GitHub Actions: What Happens on Push

### Push to `main` (no tag)

A pre-release is automatically created or updated at the `prerelease` tag.
The version string is `<last-tag>-<short-sha>` (e.g. `1.2.0-a3f91cd`).
**This does NOT submit to MPR.**

Pre-release packages are available for download on the GitHub Releases page.
Use these to share work-in-progress builds with other testers — install via
Package Manager → Install from file.

### Push a `v*` tag

Creates a full (non-prerelease) GitHub release. This IS a production release and
DOES trigger an automatic PR submission to the Mudlet Package Repository.

You generally don't need to push tags manually — use the promote workflow instead.

### Workflow dispatch (promote to production)

Go to **GitHub → Actions → "Build Package" → Run workflow**.

Enter a version number (e.g. `1.3.0`). Optionally enter release notes.

This:
1. Builds the package with that version injected
2. Creates an annotated git tag `v1.3.0`
3. Publishes a production GitHub release with the mpackage attached
4. Automatically opens a PR to the Mudlet Package Repository

You do not need to create the tag locally or push it. One UI action does everything.

---

## Mudlet Package Repository (MPR)

MPR is the community package index at `github.com/Mudlet/mudlet-package-repository`.
We maintain a fork at `github.com/tmtocloud/mudlet-package-repository`.

### How submission works

When a production release is created (tag push or workflow dispatch with version):

1. GitHub Actions clones our fork, syncs it with upstream MPR main
2. Creates a branch `fed2-tools-v<version>`
3. Copies `fed2-tools.mpackage` into `packages/`
4. Commits and pushes the branch to our fork
5. Opens a PR against `Mudlet/mudlet-package-repository`

Once the MPR maintainers merge the PR, `mpkg update` + `mpkg install fed2-tools`
in Mudlet will deliver the new version to end users.

### Required secret

The `MUDLET_REPO_PAT` secret in the fed2-tools repo settings must be a GitHub
Personal Access Token with push access to `tmtocloud/mudlet-package-repository`
and permission to open PRs against `Mudlet/mudlet-package-repository`.

### MPR validation rules

MPR's CI validates every PR. A submission fails if:

- More than one file changed in the PR
- `config.lua` is missing or malformed
- Any required field is absent: `mpackage`, `title`, `version`, `created`, `author`, `description`
- Another package with the same name but different author already exists

The `config.lua` is generated automatically by `build.ps1` from `project.json`.
Do not edit `config.lua` directly.

---

## Version Simulation

### Dev builds (no `-Version` flag)

`build.ps1` automatically derives a version string from the last git tag:

```
1.1.8-dev   ← if last tag is v1.1.8
```

The in-game update checker strips the `-dev` suffix for comparison, so `1.1.8-dev`
is treated as numerically equal to `1.1.8`. The update popup is suppressed because
the MPR version is not newer than what's installed.

### Testing a planned release version

To test locally as if you were already on `1.2.0` (prevents the update popup and
exercises any version-gated logic):

```powershell
./build.ps1 -Version 1.2.0
```

### Releasing to production

**Option A — local tag push** (triggers GitHub Actions via the `v*` tag rule):

```powershell
git tag -a v1.2.0 -m "Brief release notes here"
git push origin v1.2.0
```

**Option B — GitHub UI** (no local tag needed; CI creates the tag):

GitHub → Actions → "Build Package" → Run workflow → enter version

Both paths produce an identical release: annotated tag, GitHub release, MPR PR.

---

## Release Checklist

Before promoting a build to production:

- [ ] All intended changes are merged to `main`
- [ ] Pre-release has been downloaded and tested in a clean Mudlet profile
- [ ] Upgrade path tested: `f2t reload` from the previous production version
- [ ] Fresh install path tested: `f2t reload fresh` on a clean profile
- [ ] `project.json` author/description still accurate
- [ ] `screenshot.png` updated if the UI changed significantly
- [ ] `README.md` updated for any new user-facing commands or settings

Then go to GitHub → Actions → "Build Package" → Run workflow → enter version.

---

## Secrets & Fork Setup (one-time admin task)

If setting up this pipeline on a new fork:

1. Fork `Mudlet/mudlet-package-repository` to your GitHub account
2. Create a PAT with `repo` scope (push to fork + open PRs)
3. Add it as `MUDLET_REPO_PAT` in fed2-tools repo → Settings → Secrets → Actions
4. The fork owner is read from `github.repository_owner` in the workflow automatically
