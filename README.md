# Coffee Shop POS

REST API Point of Sales untuk coffee shop skala menengah, dibangun dengan Go dan MySQL. Fitur utamanya mencakup manajemen produk, stok, meja, promo, shift kasir, transaksi dengan pembayaran tunai maupun Midtrans Snap, serta laporan penjualan untuk Owner.

## Dokumentasi

- [PRD.md](PRD.md): kebutuhan produk, role, fitur, dan business rules
- [SCHEMA.md](SCHEMA.md): desain database MySQL
- [API_CONTRACT.md](API_CONTRACT.md): kontrak REST API `/api/v1`
- [postman_collection.json](postman_collection.json): Postman collection, beserta environment Local dan Production

## Struktur Folder

```
cmd/api/              Entry point aplikasi
config/               Konfigurasi aplikasi
internal/entity/      Domain struct
internal/repository/  Repository interface (implementasi MySQL di mysql/)
internal/service/     Business logic
internal/handler/     HTTP handler
internal/middleware/  Middleware (auth, role, logging)
internal/dto/         Struct request/response
pkg/                  Helper: database, redis, jwt, response, validator
migrations/           File SQL migration
```

## Menjalankan

```bash
cp .env.example .env
go run ./cmd/api
```
