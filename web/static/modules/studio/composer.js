// Composer command menu builder for Roundtable studio (#45).

export function mountComposerCommands({
  prefix,
  root,
  materials,
  mention,
  mentionsAvailable,
  otherCommands,
  meetingActions,
  $,
}) {
  const continuousToggle = $(prefix + "-continuous-enabled");
  const runComposer = prefix === "run";
  return window.RoundtableCommands.mount({
    root,
    button: $(prefix + "-commands"),
    commands: () => [
      { label: "添加图片", group: "材料", icon: "image", run: () => materials.pick("image") },
      { label: "添加文件", group: "材料", icon: "file", run: () => materials.pick("file") },
      {
        label: runComposer ? "@ 点名席位" : "@ 指定首席起草议程",
        group: "讨论",
        icon: "mention",
        disabled: !mentionsAvailable(),
        run: () => mention.open(),
      },
      ...otherCommands,
      {
        label: continuousToggle.checked ? "关闭持续推进" : "开启持续推进",
        group: "推进",
        icon: "continue",
        disabled: continuousToggle.disabled,
        run: () => continuousToggle.click(),
      },
      {
        label: "持续推进设置",
        group: "推进",
        icon: "sliders",
        disabled: !continuousToggle.checked || continuousToggle.disabled,
        run() {
          $(prefix + "-continuous-options").querySelector("details").open = true;
          const input = $(prefix + "-continuous-goal");
          if (runComposer) meetingActions.openSettings(input);
          else input.focus();
        },
      },
    ],
  });
}
