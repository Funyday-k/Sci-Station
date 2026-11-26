package research

import (
	"net/http"
	"time"
)

// PublicResourceClient uses the same DNS-pinned public-address transport as
// online paper imports. Keeping redirects off also keeps session tokens scoped.
func PublicResourceClient() *http.Client {
	return &http.Client{Transport: paperHTTPClient.Transport, Timeout: 10 * time.Second,
		CheckRedirect: func(req *http.Request, via []*http.Request) error { return http.ErrUseLastResponse }}
}
