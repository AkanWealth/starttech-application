package routes

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func newTestRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	// Handlers are nil: only route registration and the dependency-free
	// /ping route are exercised here.
	RegisterRoutes(r, nil, nil, nil, func(c *gin.Context) { c.Next() })
	return r
}

func TestRoutesMountedAtRootAndAPIPrefix(t *testing.T) {
	r := newTestRouter()

	registered := map[string]bool{}
	for _, route := range r.Routes() {
		registered[route.Method+" "+route.Path] = true
	}

	for _, want := range []string{
		"GET /health",
		"GET /api/v1/health",
		"GET /api/v1/ping",
		"POST /api/v1/auth/login",
		"GET /api/v1/tasks",
		"GET /api/v1/users/me",
	} {
		if !registered[want] {
			t.Errorf("route %q is not registered", want)
		}
	}
}

func TestPingRespondsUnderAPIPrefix(t *testing.T) {
	r := newTestRouter()

	for _, path := range []string{"/ping", "/api/v1/ping"} {
		w := httptest.NewRecorder()
		r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, path, nil))
		if w.Code != http.StatusOK {
			t.Errorf("GET %s = %d, want 200", path, w.Code)
		}
	}
}
