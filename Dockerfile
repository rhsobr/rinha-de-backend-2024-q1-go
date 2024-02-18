FROM golang:1.22-alpine AS builder

WORKDIR /usr/src/app

COPY go.* ./
RUN go mod download

COPY . ./

RUN go build -v -o server

FROM alpine:3

RUN apk --no-cache add ca-certificates

# for health check
RUN apk --update --no-cache add curl 

WORKDIR /usr/src/app

COPY --from=builder /usr/src/app/ .

CMD ["/usr/src/app/server"]

EXPOSE 3000