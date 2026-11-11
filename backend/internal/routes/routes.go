package routes

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"

	"github.com/Innocent9712/much-to-do/Server/MuchToDo/docs"
	"github.com/Innocent9712/much-to-do/Server/MuchToDo/internal/handlers"
)

// APIPrefix is the path CloudFront forwards to the backend (/api/*).
// The frontend calls relative URLs such as /api/v1/health.
const APIPrefix = "/api/v1"

// RegisterRoutes mounts all application routes twice: at the root (local
// development, Kubernetes probes) and under /api/v1 (traffic through CloudFront).
func RegisterRoutes(
	router *gin.Engine,
	userHandler *handlers.UserHandler,
	todoHandler *handlers.TodoHandler,
	healthHandler *handlers.HealthHandler,
	authMiddleware gin.HandlerFunc,
) {
	register(&router.RouterGroup, userHandler, todoHandler, healthHandler, authMiddleware)
	register(router.Group(APIPrefix), userHandler, todoHandler, healthHandler, authMiddleware)
}

func register(
	r *gin.RouterGroup,
	userHandler *handlers.UserHandler,
	todoHandler *handlers.TodoHandler,
	healthHandler *handlers.HealthHandler,
	authMiddleware gin.HandlerFunc,
) {
	// Public routes
	r.GET("/health", healthHandler.CheckHealth)
	// Liveness: answers as long as the process is up, without touching dependencies.
	r.GET("/ping", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"message": "pong"})
	})

	// Swagger documentation route
	r.GET("/swagger/*any", func(c *gin.Context) {
		scheme := "http"
		if c.Request.TLS != nil || strings.HasPrefix(c.Request.Header.Get("X-Forwarded-Proto"), "https") {
			scheme = "https"
		}

		docs.SwaggerInfo.Host = c.Request.Host
		docs.SwaggerInfo.Schemes = []string{scheme}

		ginSwagger.WrapHandler(swaggerFiles.Handler)(c)
	})

	authRoutes := r.Group("/auth")
	{
		authRoutes.POST("/register", userHandler.Register)
		authRoutes.POST("/login", userHandler.Login)
		authRoutes.POST("/logout", userHandler.Logout)
		authRoutes.GET("/username-check/:username", userHandler.CheckUsernameAvailability)
	}

	// Protected routes
	protected := r.Group("")
	protected.Use(authMiddleware)
	{
		// Task routes (named /tasks to avoid clashing with the frontend /todos route)
		taskRoutes := protected.Group("/tasks")
		{
			taskRoutes.POST("", todoHandler.CreateTodo)
			taskRoutes.GET("", todoHandler.GetAllTodos)
			taskRoutes.GET("/:id", todoHandler.GetTodoByID)
			taskRoutes.PUT("/:id", todoHandler.UpdateTodo)
			taskRoutes.DELETE("/:id", todoHandler.DeleteTodo)
		}

		userRoutes := protected.Group("/users")
		{
			userRoutes.GET("/me", userHandler.GetCurrentUser)
			userRoutes.PUT("/me", userHandler.UpdateUser)
			userRoutes.PUT("/me/password", userHandler.ChangePassword)
			userRoutes.DELETE("/me", userHandler.DeleteUser)
		}
	}
}
