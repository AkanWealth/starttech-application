package config

import "testing"

func TestLoadConfigReadsEnvironment(t *testing.T) {
	t.Setenv("MONGO_URI", "mongodb+srv://user:pass@cluster.example.net")
	t.Setenv("REDIS_HOST", "starttech-redis.abc123.0001.use1.cache.amazonaws.com")
	t.Setenv("ALLOWED_ORIGINS", "https://a.example.com, https://b.example.com")

	cfg, err := LoadConfig(t.TempDir())
	if err != nil {
		t.Fatalf("LoadConfig returned error: %v", err)
	}

	if cfg.MongoURI != "mongodb+srv://user:pass@cluster.example.net" {
		t.Errorf("MongoURI = %q, want value from env", cfg.MongoURI)
	}
	if want := "starttech-redis.abc123.0001.use1.cache.amazonaws.com:6379"; cfg.RedisAddr != want {
		t.Errorf("RedisAddr = %q, want %q", cfg.RedisAddr, want)
	}
	if cfg.ServerPort != "8080" {
		t.Errorf("ServerPort = %q, want default 8080", cfg.ServerPort)
	}
	if cfg.LogFormat != "json" {
		t.Errorf("LogFormat = %q, want default json", cfg.LogFormat)
	}
	if len(cfg.AllowedOrigins) != 2 || cfg.AllowedOrigins[1] != "https://b.example.com" {
		t.Errorf("AllowedOrigins = %v, want two trimmed entries", cfg.AllowedOrigins)
	}
}

func TestResolveRedisAddr(t *testing.T) {
	tests := []struct {
		name, addr, host, port, want string
	}{
		{"host only uses default port", "", "redis", "", "redis:6379"},
		{"host and port", "", "redis", "6380", "redis:6380"},
		{"host with port", "", "redis:7000", "6379", "redis:7000"},
		{"falls back to REDIS_ADDR", "localhost:6379", "", "6379", "localhost:6379"},
		{"host wins over addr", "localhost:6379", "elasticache", "6379", "elasticache:6379"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := resolveRedisAddr(tc.addr, tc.host, tc.port); got != tc.want {
				t.Errorf("resolveRedisAddr() = %q, want %q", got, tc.want)
			}
		})
	}
}
