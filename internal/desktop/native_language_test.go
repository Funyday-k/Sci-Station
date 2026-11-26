package desktop

import "testing"

func TestInterfaceLanguagePreferencePrecedence(t *testing.T) {
	for _, test := range []struct{ preference, system, want string }{
		{"system", "zh-TW", "zh-Hans"}, {"system", "EN-GB", "en"}, {"system", "ja-JP", "en"},
		{"en", "zh-CN", "en"}, {"zh-Hans", "en-HK", "zh-Hans"},
	} {
		if got := resolveInterfaceLanguage(test.preference, test.system); got != test.want {
			t.Fatalf("resolve(%q, %q) = %q, want %q", test.preference, test.system, got, test.want)
		}
	}
}

func TestNativeMenuUsesWorkspaceInterfaceCatalog(t *testing.T) {
	for _, test := range []struct{ key, en, zh string }{
		{"toolbarWorkspace", "Workspace", "工作区"}, {"toolbarOpenWorkspace", "Open Workspace", "打开工作区"},
		{"toolbarNewProject", "New Project", "新建项目"}, {"menuCopyCitation", "Copy Citation", "复制引用"},
		{"toolbarInspector", "Inspector", "检查器"}, {"toolbarSave", "Save", "保存"},
	} {
		if en, zh := interfaceText("en", test.key), interfaceText("zh-Hans", test.key); en != test.en || zh != test.zh {
			t.Fatalf("%s = %q, %q; want %q, %q", test.key, en, zh, test.en, test.zh)
		}
	}
}
