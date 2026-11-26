package gateway

import "testing"

func TestCompatibleProviderAcceptsTLSAndLiteralLoopback(t *testing.T) {
	cases := []struct {
		given, want string
	}{
		{"https://Provider.Example/gateway/v1/", "https://provider.example/gateway/v1"},
		{"http://localhost:8383/v1/", "http://127.0.0.1:8383/v1"},
		{"http://[::1]:8383/v1", "http://[::1]:8383/v1"},
		{"http://localhost.example/v1", ""},
		{"http://192.168.0.1/v1", ""},
		{"https://provider.example/path?key=fixture", ""},
		{"https://username@provider.example/v1", ""},
		{"ftp://provider.example/v1", ""},
		{"https://provider.example:70000/v1", ""},
		{"https://provider.example/v1#other", ""},
	}
	for _, tc := range cases {
		profile, err := NormalizeCompatibleProfile(CompatibleProfile{Name: "Fixture", BaseURL: tc.given, Model: "model/id"})
		if tc.want == "" {
			if err == nil {
				t.Errorf("accepted unsupported endpoint %q", tc.given)
			}
		} else if err != nil || profile.BaseURL != tc.want {
			t.Errorf("got %q for %q, want %q: %v", profile.BaseURL, tc.given, tc.want, err)
		}
	}
}
