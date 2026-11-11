package config

import (
	"net"
	"strings"

	"github.com/spf13/viper"
)

// Config stores all configuration of the application.
type Config struct {
	ServerPort         string   `mapstructure:"PORT"`
	MongoURI           string   `mapstructure:"MONGO_URI"`
	DBName             string   `mapstructure:"DB_NAME"`
	JWTSecretKey       string   `mapstructure:"JWT_SECRET_KEY"`
	JWTExpirationHours int      `mapstructure:"JWT_EXPIRATION_HOURS"`
	EnableCache        bool     `mapstructure:"ENABLE_CACHE"`
	RedisHost          string   `mapstructure:"REDIS_HOST"`
	RedisPort          string   `mapstructure:"REDIS_PORT"`
	RedisAddr          string   `mapstructure:"REDIS_ADDR"`
	RedisPassword      string   `mapstructure:"REDIS_PASSWORD"`
	LogLevel           string   `mapstructure:"LOG_LEVEL"`
	LogFormat          string   `mapstructure:"LOG_FORMAT"`
	CookieDomains      []string `mapstructure:"COOKIE_DOMAINS"`
	SecureCookie       bool     `mapstructure:"SECURE_COOKIE"`
	AllowedOrigins     []string `mapstructure:"ALLOWED_ORIGINS"`
}

// envKeys lists every supported environment variable. Viper's Unmarshal only
// sees keys it already knows about, so each one is bound explicitly. Without
// this, values such as MONGO_URI are ignored when no .env file is present
// (for example inside a container).
var envKeys = []string{
	"PORT", "MONGO_URI", "DB_NAME", "JWT_SECRET_KEY", "JWT_EXPIRATION_HOURS",
	"ENABLE_CACHE", "REDIS_HOST", "REDIS_PORT", "REDIS_ADDR", "REDIS_PASSWORD",
	"LOG_LEVEL", "LOG_FORMAT", "COOKIE_DOMAINS", "SECURE_COOKIE", "ALLOWED_ORIGINS",
}

// LoadConfig reads configuration from an optional .env file and environment variables.
// Environment variables take precedence over the file.
func LoadConfig(path string) (config Config, err error) {
	v := viper.New()
	v.AddConfigPath(path)
	v.SetConfigName(".env")
	v.SetConfigType("env")

	v.AutomaticEnv()
	for _, key := range envKeys {
		if err = v.BindEnv(key); err != nil {
			return
		}
	}

	// Set default values
	v.SetDefault("PORT", "8080")
	v.SetDefault("DB_NAME", "much_todo_db")
	v.SetDefault("ENABLE_CACHE", false)
	v.SetDefault("REDIS_PORT", "6379")
	v.SetDefault("JWT_EXPIRATION_HOURS", 72)
	v.SetDefault("LOG_LEVEL", "INFO")
	v.SetDefault("LOG_FORMAT", "json")
	v.SetDefault("COOKIE_DOMAINS", []string{"localhost"})
	v.SetDefault("SECURE_COOKIE", false)
	v.SetDefault("ALLOWED_ORIGINS", []string{"http://localhost:5173"})

	err = v.ReadInConfig()
	if err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
			return
		}
		err = nil
	}

	err = v.Unmarshal(&config)
	if err != nil {
		return
	}

	// Handle comma-separated strings for slices if viper didn't split them
	if allowedOrigins := v.GetString("ALLOWED_ORIGINS"); allowedOrigins != "" {
		config.AllowedOrigins = splitList(allowedOrigins)
	}
	if cookieDomains := v.GetString("COOKIE_DOMAINS"); cookieDomains != "" {
		config.CookieDomains = splitList(cookieDomains)
	}

	config.RedisAddr = resolveRedisAddr(config.RedisAddr, config.RedisHost, config.RedisPort)

	return
}

// resolveRedisAddr builds the Redis address. REDIS_HOST (the ElastiCache
// endpoint) wins over the legacy REDIS_ADDR. REDIS_HOST may already include a port.
func resolveRedisAddr(addr, host, port string) string {
	host = strings.TrimSpace(host)
	if host == "" {
		return addr
	}
	if _, _, err := net.SplitHostPort(host); err == nil {
		return host
	}
	if port == "" {
		port = "6379"
	}
	return net.JoinHostPort(host, port)
}

func splitList(s string) []string {
	var cleaned []string
	for _, p := range strings.Split(s, ",") {
		trimmed := strings.Trim(strings.TrimSpace(p), "\"'")
		if trimmed != "" {
			cleaned = append(cleaned, trimmed)
		}
	}
	return cleaned
}
