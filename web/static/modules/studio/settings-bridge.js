// Settings & appearance synchronization bridge for Roundtable studio (#45).

export function syncAppearanceFromSettings(appearance, settings) {
  if (!settings || !appearance) return;
  appearance.setMode(settings.appearance || "system", true);
  appearance.setColorTheme(settings.color_theme || "iris", true);
  appearance.setTextSize(settings.text_size || "standard", true);
}
