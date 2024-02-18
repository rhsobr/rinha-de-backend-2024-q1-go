package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/gin-gonic/gin/binding"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/subosito/gotenv"
)

type AdicionaTransacaoReq struct {
	Tipo      string `json:"tipo" binding:"required"`
	Valor     int32  `json:"valor" binding:"required"`
	Descricao string `json:"descricao" binding:"required"`
}

var dbRW *pgxpool.Pool

func GetenvOrDefault(name, def string) string {
	value := os.Getenv(name)

	if len(value) > 0 {
		return value
	}

	return def
}

func validaId(ctx *gin.Context) {
	idStr := ctx.Param("id")

	id, err := strconv.Atoi(idStr)

	if err != nil || id > 5 {
		ctx.String(http.StatusNotFound, "id")
		return
	}

	ctx.Set("id", id)
	ctx.Next()
}

var ATUALIZA_SALDO_QUERY string = "SELECT atualiza_saldo($1,$2,$3,$4) AS result"
var GERA_EXTRATO_QUERY string = "SELECT gera_extrato($1) AS result"

func init() {
	gotenv.Load()

	hostname, _ := os.Hostname()

	dbConnString := os.Getenv("DATABASE_URL")

	dbConnStringRW := strings.Replace(dbConnString, "%app%", hostname+"-rw", -1)

	poolConfigRW, err := pgxpool.ParseConfig(dbConnStringRW)

	if err != nil {
		fmt.Fprintf(os.Stderr, "Unable to connect to database: %v\n", err)
		os.Exit(1)
	}

	maxRWConnections, _ := strconv.Atoi(GetenvOrDefault("DB_MAX_RW_CONNECTIONS", "3"))

	poolConfigRW.MinConns = 1
	poolConfigRW.MaxConns = int32(maxRWConnections)

	dbRW, err = pgxpool.NewWithConfig(context.Background(), poolConfigRW)

	if err != nil {
		fmt.Fprintf(os.Stderr, "Unable to connect to database: %v\n", err)
		os.Exit(1)
	}

	body, err := os.ReadFile("./database/functions.sql")

	if err != nil {
		fmt.Fprintf(os.Stderr, "Unable to load database functions: %v\n", err)
		os.Exit(1)
	}

	dbRW.Exec(context.Background(), string(body))
}

func main() {

	router := gin.New()

	router.Use(gin.Recovery())

	router.GET("/healthcheck", func(c *gin.Context) {
		var result string

		err := dbRW.QueryRow(context.Background(), GERA_EXTRATO_QUERY, 1).Scan(&result)

		if err != nil {
			c.AbortWithError(http.StatusBadRequest, err)
			return
		}

		c.String(http.StatusOK, "")
	})

	clientesRoute := router.Group("/clientes/:id", validaId)

	{
		clientesRoute.GET("/extrato", func(c *gin.Context) {
			var result string

			err := dbRW.QueryRow(context.Background(), GERA_EXTRATO_QUERY, c.MustGet("id").(int)).Scan(&result)

			if err == pgx.ErrNoRows {
				c.String(http.StatusNotFound, err.Error())
				return
			}

			if err != nil {
				c.String(http.StatusBadRequest, err.Error())
				return
			}

			c.Header("Content-Type", "application/json")
			c.String(http.StatusOK, result)
		})

		clientesRoute.POST("/transacoes", func(c *gin.Context) {
			payload := AdicionaTransacaoReq{}

			if err := c.ShouldBindWith(&payload, binding.JSON); err != nil {
				c.String(http.StatusUnprocessableEntity, "bind")
				return
			}

			if payload.Tipo != "d" && payload.Tipo != "c" {
				c.String(http.StatusUnprocessableEntity, "tipo")
				return
			}

			if payload.Valor <= 0 {
				c.String(http.StatusUnprocessableEntity, "valor")
				return
			}

			lengthDescricao := len(payload.Descricao)
			if lengthDescricao == 0 || lengthDescricao > 10 {
				c.String(http.StatusUnprocessableEntity, "descricao")
				return
			}

			var result string

			err := dbRW.QueryRow(context.Background(), ATUALIZA_SALDO_QUERY, c.MustGet("id").(int), payload.Tipo, payload.Valor, payload.Descricao).Scan(&result)

			if err != nil {
				c.AbortWithError(http.StatusUnprocessableEntity, err)
				return
			}

			c.Header("Content-Type", "application/json")
			c.String(http.StatusOK, result)
		})
	}

	port := GetenvOrDefault("API_PORT", "3000")

	router.Run(":" + port)
}
