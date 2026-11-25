# Shared macOS container operations. Callers own the temporary directories.

release_zip() {
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$1" "$2"
}

release_dmg() {
  local app="$1" dmg="$2" staging="$3"
  mkdir -p "$staging"
  /usr/bin/ditto "$app" "$staging/Sci-Station.app"
  ln -s /Applications "$staging/Applications"
  /usr/bin/hdiutil create -volname Sci-Station -srcfolder "$staging" -ov -format UDZO "$dmg"
  /usr/bin/hdiutil verify "$dmg"
}

release_checksum() {
  local artifact="$1"
  (cd "$(dirname "$artifact")" && shasum -a 256 "$(basename "$artifact")")
}

verify_release_checksum() {
  local artifact="$1" sum
  sum="$(release_checksum "$artifact")"
  if [[ ! -f "$artifact.sha256" || "$sum" != "$(cat "$artifact.sha256")" ]]; then
    printf 'Invalid or missing SHA-256 sidecar for %s.\n' "$artifact" >&2
    return 1
  fi
  printf 'SHA-256 verified: %s\n' "$artifact"
}

write_release_outputs() {
  local app="$1" zip="$2" dmg="$3"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf 'app_path=%s\nzip_path=%s\ndmg_path=%s\nzip_checksum_path=%s.sha256\ndmg_checksum_path=%s.sha256\n' \
      "$app" "$zip" "$dmg" "$zip" "$dmg" >>"$GITHUB_OUTPUT"
  fi
}

RELEASE_MOUNT_DEVICE=""
RELEASE_SOURCE_APP=""

open_release_app() {
  local artifact="$1" scratch="$2" mount_output
  case "$artifact" in
    *.app) RELEASE_SOURCE_APP="$artifact" ;;
    *.dmg)
      mkdir -p "$scratch/mount"
      mount_output="$(/usr/bin/hdiutil attach -nobrowse -readonly -mountpoint "$scratch/mount" "$artifact")" || return
      RELEASE_MOUNT_DEVICE="$(printf '%s\n' "$mount_output" | awk '/^\/dev\// { print $1; exit }')"
      if [[ -z "$RELEASE_MOUNT_DEVICE" ]]; then
        /usr/bin/hdiutil detach "$scratch/mount" -quiet || true
        printf 'Unable to identify the mounted release disk image.\n' >&2
        return 1
      fi
      RELEASE_SOURCE_APP="$scratch/mount/Sci-Station.app"
      ;;
    *.zip)
      mkdir -p "$scratch/extracted"
      /usr/bin/ditto -x -k "$artifact" "$scratch/extracted" || return
      RELEASE_SOURCE_APP="$scratch/extracted/Sci-Station.app"
      ;;
    *) printf 'Unsupported release artifact: %s\n' "$artifact" >&2; return 2 ;;
  esac
  if [[ ! -d "$RELEASE_SOURCE_APP" || ( "$artifact" != *.app && -L "$RELEASE_SOURCE_APP" ) ]]; then
    printf 'Release artifact has no Sci-Station.app bundle: %s\n' "$artifact" >&2
    return 1
  fi
}

close_release_app() {
  if [[ -n "$RELEASE_MOUNT_DEVICE" ]]; then
    /usr/bin/hdiutil detach "$RELEASE_MOUNT_DEVICE" -quiet || return
    RELEASE_MOUNT_DEVICE=""
  fi
  RELEASE_SOURCE_APP=""
}
