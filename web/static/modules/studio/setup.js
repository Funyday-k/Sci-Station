// Draft setup and mode-transfer helpers for Roundtable studio (#45).

export function modeMaterialIDs(materials) {
  return (materials || []).map(({ id }) => id);
}

export function modeMaterialStamp(materials) {
  return JSON.stringify(modeMaterialIDs(materials));
}

export function modeFollowupKey(id) {
  return `sci-station.roundtable-followup.v1.${id}`;
}
