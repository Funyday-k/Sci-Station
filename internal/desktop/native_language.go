package desktop

import (
	"encoding/json"
	"strings"

	"scistation.local/desktop/web"
)

var interfaceCatalog = func() map[string]map[string]string {
	data, err := web.Assets.ReadFile("static/interface-catalog.json")
	if err != nil {
		panic(err)
	}
	var catalog map[string]map[string]string
	if err := json.Unmarshal(data, &catalog); err != nil {
		panic(err)
	}
	return catalog
}()

// Swift uses the first preferred system language and defaults to English when
// that language is neither simplified nor traditional Chinese.
func resolveInterfaceLanguage(preference, system string) string {
	if preference == "en" || preference == "zh-Hans" {
		return preference
	}
	if strings.HasPrefix(strings.ToLower(system), "zh") {
		return "zh-Hans"
	}
	return "en"
}

func interfaceText(language, key string) string {
	if value := interfaceCatalog[key][language]; value != "" {
		return value
	}
	return interfaceCatalog[key]["en"]
}
