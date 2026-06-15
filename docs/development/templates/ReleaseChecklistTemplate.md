# Release Checklist: <version>

## Metadata

- Version:
- Build:
- Branch:
- Tag:
- Commit:
- Date:
- Channel: beta / rc / stable

## Version checks

- [ ] `MARKETING_VERSION` matches release version.
- [ ] `CURRENT_PROJECT_VERSION` incremented.
- [ ] Diagnostics export reports expected version/build.
- [ ] `CHANGELOG.md` updated.
- [ ] `releases/<version>.md` updated.

## Automated validation

- [ ] `swift run --quiet SciStationCoreTestRunner`
- [ ] `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -configuration Debug -destination 'platform=macOS' build`
- [ ] AgentRuntime pytest if affected.
- [ ] UI smoke if affected.

## Manual validation

- [ ] New workspace can be created.
- [ ] Existing workspace can be opened.
- [ ] Library import path works.
- [ ] Wiki save/reopen works.
- [ ] Recommendation and reading Todo affected paths work.
- [ ] Settings and diagnostics export work.
- [ ] No obvious secret/path leak in debug events or diagnostics.

## Packaging

- [ ] Build artifact created.
- [ ] Artifact name includes version and build.
- [ ] Signing status recorded.
- [ ] Notarization status recorded, if applicable.
- [ ] Release notes attached.

## Final decision

- [ ] Ship.
- [ ] Hold due to blockers.

## Blockers

- 

## Known issues

- 
