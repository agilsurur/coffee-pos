# API Contract — Coffee POS

| Item | Keterangan |
|---|---|
| Acuan | [PRD.md](PRD.md), [SCHEMA.md](SCHEMA.md) |
| Versi API | v1 |
| Format | JSON (`Content-Type: application/json`), kecuali upload foto (multipart) dan export (CSV) |
| Tanggal | 27 Oktober 2026 |

---

## 1. Base URL dan Versioning

```
https://<host>/api/v1
```

| Environment | Base URL |
|---|---|
| Local | `http://localhost:8080/api/v1` |
| Staging | `https://staging.<domain>/api/v1` |
| Production | `https://api.<domain>/api/v1` |

- Versi ditulis di path (`/api/v1`). Perubahan yang **breaking** (menghapus field, mengubah tipe, mengubah arti status) dilakukan di `/api/v2`. Perubahan yang tidak breaking, seperti menambah field baru di response atau endpoint baru, dilakukan di v1. Client wajib mengabaikan field yang tidak dikenalnya.
- Semua path di dokumen ini relatif terhadap base URL. Contoh: `POST /auth/login` berarti `POST https://<host>/api/v1/auth/login`.

---

## 2. Authentication

### 2.1 Header
Semua endpoint selain yang bertanda **Public** wajib menyertakan:

```
Authorization: Bearer <access_token>
```

### 2.2 Token
- `access_token` berupa JWT (HS256) yang didapat dari `POST /auth/login`.
- Masa berlaku **12 jam**, cukup untuk satu shift penuh. Versi ini tidak memakai refresh token. Setelah token kedaluwarsa, user login ulang.
- Isi claim:

```json
{
  "sub": "0192f0a1-7b3c-7c1e-9f2a-1c2d3e4f5a6b",
  "role": "CASHIER",
  "tv": 3,
  "iat": 1761552000,
  "exp": 1761595200
}
```

- `tv` adalah `users.token_version`. Di setiap request, server mencocokkan `tv` dengan nilai di database dan memastikan user masih `ACTIVE`. Token langsung tidak berlaku setelah logout, ganti password, reset password oleh Owner, atau user dinonaktifkan (PRD 3.5).

### 2.3 Error otentikasi & otorisasi (berlaku di semua protected endpoint)

| HTTP | Kapan | Contoh `message` |
|---|---|---|
| 401 | Header `Authorization` tidak ada atau formatnya salah | `"Token tidak ditemukan. Silakan login."` |
| 401 | Token kedaluwarsa | `"Sesi Anda telah berakhir. Silakan login kembali."` |
| 401 | Signature token tidak valid, `tv` tidak cocok (sudah logout atau password diganti), atau user dinonaktifkan | `"Sesi tidak valid. Silakan login kembali."` |
| 403 | Token valid tetapi role tidak berhak mengakses endpoint ini | `"Anda tidak memiliki akses ke fitur ini."` |

Semua error di atas memakai format error umum (3.5) dan **tidak diulang** di daftar error setiap endpoint. Pada 401, client menghapus token dan mengarahkan user ke halaman login.

---

## 3. Standard Response Format

Semua endpoint memakai **empat bentuk response** berikut. Satu-satunya pengecualian adalah export CSV yang sukses (lihat 4.8).

### 3.1 Sukses — single resource / aksi

```json
{
  "success": true,
  "message": "Produk berhasil dibuat",
  "data": {
    "id": "0192f0d4-0001-7abc-8def-000000000001",
    "name": "Es Kopi Susu Aren"
  }
}
```

Untuk aksi yang tidak mengembalikan data (mis. logout), `data` bernilai `null`:

```json
{
  "success": true,
  "message": "Logout berhasil",
  "data": null
}
```

### 3.2 Sukses — list dengan pagination

```json
{
  "success": true,
  "message": "Data produk berhasil diambil",
  "data": [
    { "id": "0192f0d4-0001-...", "name": "Es Kopi Susu Aren" },
    { "id": "0192f0d4-0002-...", "name": "Americano" }
  ],
  "meta": {
    "page": 1,
    "per_page": 20,
    "total_items": 57,
    "total_pages": 3
  }
}
```

- `meta` hanya muncul di endpoint list yang memakai pagination.
- Query param pagination: `page` (default `1`) dan `per_page` (default `20`, maksimal `100`).
- List kecil yang tidak di-paginate (mis. `GET /promos/active`) mengembalikan array di `data` tanpa `meta`.

### 3.3 Error validasi (HTTP 422)

```json
{
  "success": false,
  "message": "Data yang dikirim tidak valid",
  "errors": {
    "price": ["Harga harus berupa bilangan bulat >= 0"],
    "category_id": ["Kategori wajib diisi"],
    "items.1.quantity": ["Stok tidak cukup, tersedia 1"]
  }
}
```

- `errors` adalah object dengan **key = nama field** di request dan **value = array pesan**. Satu field bisa punya lebih dari satu pesan.
- Field di dalam array memakai notasi titik dengan index mulai dari 0, mis. `items.1.quantity` untuk item kedua.
- Client menampilkan setiap pesan di bawah input yang sesuai.

### 3.4 Error umum (HTTP 400, 401, 403, 404, 429, 500)

```json
{
  "success": false,
  "message": "Anda belum membuka shift. Buka shift terlebih dahulu."
}
```

- `message` berbahasa Indonesia dan siap ditampilkan langsung ke user.
- Setiap response (sukses maupun error) membawa header `X-Request-ID` untuk penelusuran log. Saat melaporkan bug, sertakan nilai header ini.

### 3.5 HTTP Status Code

| HTTP | Format body | Dipakai untuk |
|---|---|---|
| **200** | Sukses (3.1 / 3.2) | `GET`, `PUT`, `PATCH`, `DELETE`, dan `POST` yang **tidak** membuat resource baru (login, logout, checkout, cancel, tutup shift, sync, webhook) |
| **201** | Sukses (3.1) | `POST` yang membuat resource baru |
| **400** | Error umum (3.4) | Request tidak valid: body bukan JSON yang valid, atau aksi tidak bisa dijalankan karena **kondisi data saat ini** dan tidak berkaitan dengan field tertentu di request (lihat 3.6) |
| **401** | Error umum | Tidak ada token, token kedaluwarsa atau tidak valid, login gagal, atau signature webhook tidak valid |
| **403** | Error umum | Token valid tetapi role tidak berhak |
| **404** | Error umum | Resource tidak ada, sudah di-soft delete, atau milik cashier lain |
| **422** | Error validasi (3.3) | Validasi gagal pada **field tertentu** di request, termasuk nilai duplikat, file tidak valid, stok tidak cukup untuk item tertentu, dan promo tidak memenuhi syarat |
| **429** | Error umum | Rate limit terlampaui |
| **500** | Error umum | Error server, termasuk kegagalan saat menghubungi Midtrans |

Status code lain (mis. 204, 409, 413, 415, 502) **tidak dipakai**.

### 3.6 Aturan 400 vs 422

- **422:** kesalahan bisa ditunjuk ke **field di request**, sehingga dikembalikan dalam `errors`. Contoh: SKU duplikat (`errors.sku`), meja sedang dipakai saat membuat order (`errors.table_id`), stok tidak cukup (`errors["items.0.quantity"]`).
- **400:** request-nya benar, tetapi aksi ditolak karena **kondisi data**, dan tidak ada field yang bisa disalahkan. Contoh: membuat order tanpa shift terbuka, mengubah order yang sudah checkout, menghapus kategori yang masih punya produk.

Pemetaan kondisi bisnis yang sering muncul:

| Kondisi | HTTP | Format |
|---|---|---|
| Body bukan JSON yang valid | 400 | umum |
| Nilai unik sudah dipakai (SKU, username, nomor meja, nama kategori, kode promo) | 422 | `errors.<field>` |
| File foto > 2 MB atau bukan JPG/PNG/WebP | 422 | `errors.photo` |
| Meja dipakai order aktif lain (saat membuat order) | 422 | `errors.table_id` |
| Produk nonaktif/dihapus (saat membuat order atau mengubah item) | 422 | `errors["items.N.product_id"]` |
| Stok tidak cukup (saat membuat order atau mengubah item) | 422 | `errors["items.N.quantity"]` |
| Promo tidak aktif atau subtotal di bawah minimum (saat memasang promo) | 422 | `errors.promo_id` |
| Produk tidak melacak stok (input pergerakan stok) | 422 | `errors.product_id` |
| Cashier belum membuka shift | 400 | umum |
| Cashier sudah punya shift terbuka | 400 | umum |
| Masih ada order `PENDING`/`FAILED` saat tutup shift | 400 | umum |
| Order sudah checkout, item/promo terkunci (BR-08) | 400 | umum |
| Order sudah lunas, sudah dibatalkan, atau status tidak memungkinkan aksi | 400 | umum |
| Produk, stok, atau promo tidak valid lagi saat checkout | 400 | umum, `message` menyebut produk/promo yang bermasalah |
| Kategori masih punya produk / promo sudah pernah dipakai | 400 | umum |
| Meja sedang dipakai (saat menonaktifkan atau menghapus meja) | 400 | umum |
| Cashier masih punya shift terbuka (saat dinonaktifkan) | 400 | umum |
| Username/password salah atau akun nonaktif saat login | 401 | umum |
| Midtrans error atau tidak bisa dihubungi | 500 | umum |

### 3.7 Konvensi `message`

| Jenis endpoint | Pola `message` | Contoh |
|---|---|---|
| `GET` list | `Data <resource> berhasil diambil` | `"Data produk berhasil diambil"` |
| `GET` detail | `Detail <resource> berhasil diambil` | `"Detail order berhasil diambil"` |
| `POST` create | `<Resource> berhasil dibuat` | `"Kategori berhasil dibuat"` |
| `PUT` / `PATCH` | `<Resource> berhasil diperbarui` | `"Status meja berhasil diperbarui"` |
| `DELETE` | `<Resource> berhasil dihapus` | `"Produk berhasil dihapus"` |
| Aksi | Kalimat spesifik | `"Shift berhasil ditutup"` |

Client menampilkan `message` sebagai toast/notifikasi untuk aksi yang mengubah data. `message` pada `GET` boleh diabaikan oleh client.

### 3.8 Konvensi Data

| Hal | Konvensi |
|---|---|
| ID | String UUID, mis. `"0192f0a1-7b3c-7c1e-9f2a-1c2d3e4f5a6b"` |
| Uang | **Integer dalam sen**, sama seperti di database. Rp 25.000 dikirim sebagai `2500000`. Client membagi 100 untuk tampilan. Tidak ada angka desimal di API |
| Waktu (response) | ISO 8601 UTC, mis. `"2026-10-27T08:30:00Z"` |
| Tanggal (query param) | `YYYY-MM-DD`, ditafsirkan dalam zona waktu outlet `Asia/Jakarta` (BR-02). `end_date` bersifat inklusif |
| Nama field | `snake_case` |
| Enum | `UPPER_SNAKE_CASE`, nilainya sama dengan ENUM di SCHEMA.md |
| Field nullable | Selalu dikirim dengan nilai `null`, tidak dihilangkan |

---

## 4. Daftar Endpoint

Di setiap endpoint, `<Category>`, `<Product>`, dan seterusnya merujuk ke objek yang didefinisikan di awal domainnya.

### 4.0 Ringkasan

| Domain | Method | Path | Akses | Sukses |
|---|---|---|---|---|
| Auth | POST | `/auth/login` | Public | 200 |
| Auth | POST | `/auth/logout` | Owner, Cashier | 200 |
| Auth | GET | `/auth/me` | Owner, Cashier | 200 |
| Auth | PUT | `/auth/password` | Owner, Cashier | 200 |
| Categories | GET | `/categories` | Owner, Cashier | 200 |
| Categories | GET | `/categories/{id}` | Owner | 200 |
| Categories | POST | `/categories` | Owner | 201 |
| Categories | PUT | `/categories/{id}` | Owner | 200 |
| Categories | DELETE | `/categories/{id}` | Owner | 200 |
| Products | GET | `/products` | Owner, Cashier | 200 |
| Products | GET | `/products/{id}` | Owner, Cashier | 200 |
| Products | POST | `/products` | Owner | 201 |
| Products | PUT | `/products/{id}` | Owner | 200 |
| Products | PATCH | `/products/{id}/status` | Owner | 200 |
| Products | DELETE | `/products/{id}` | Owner | 200 |
| Products | POST | `/products/{id}/photo` | Owner | 200 |
| Products | DELETE | `/products/{id}/photo` | Owner | 200 |
| Stock | POST | `/stock/movements` | Owner | 201 |
| Stock | GET | `/stock/movements` | Owner | 200 |
| Stock | GET | `/stock/alerts` | Owner | 200 |
| Tables | GET | `/tables` | Owner, Cashier | 200 |
| Tables | GET | `/tables/{id}` | Owner | 200 |
| Tables | POST | `/tables` | Owner | 201 |
| Tables | PUT | `/tables/{id}` | Owner | 200 |
| Tables | PATCH | `/tables/{id}/status` | Owner | 200 |
| Tables | DELETE | `/tables/{id}` | Owner | 200 |
| Users | GET | `/users` | Owner | 200 |
| Users | GET | `/users/{id}` | Owner | 200 |
| Users | POST | `/users` | Owner | 201 |
| Users | PUT | `/users/{id}` | Owner | 200 |
| Users | PATCH | `/users/{id}/status` | Owner | 200 |
| Users | POST | `/users/{id}/reset-password` | Owner | 200 |
| Promos | GET | `/promos` | Owner | 200 |
| Promos | GET | `/promos/active` | Owner, Cashier | 200 |
| Promos | GET | `/promos/{id}` | Owner | 200 |
| Promos | POST | `/promos` | Owner | 201 |
| Promos | PUT | `/promos/{id}` | Owner | 200 |
| Promos | PATCH | `/promos/{id}/status` | Owner | 200 |
| Promos | DELETE | `/promos/{id}` | Owner | 200 |
| Reports | GET | `/reports/summary` | Owner | 200 |
| Reports | GET | `/reports/revenue` | Owner | 200 |
| Reports | GET | `/reports/top-products` | Owner | 200 |
| Reports | GET | `/reports/cashiers` | Owner | 200 |
| Reports | GET | `/reports/export/{report_type}` | Owner | 200 (CSV) |
| Shifts | POST | `/shifts/open` | Cashier | 201 |
| Shifts | GET | `/shifts/current` | Cashier | 200 |
| Shifts | GET | `/shifts/current/summary` | Cashier | 200 |
| Shifts | POST | `/shifts/current/close` | Cashier | 200 |
| Shifts | GET | `/shifts` | Owner | 200 |
| Shifts | GET | `/shifts/{id}` | Owner | 200 |
| Orders | POST | `/orders` | Cashier | 201 |
| Orders | GET | `/orders` | Owner, Cashier | 200 |
| Orders | GET | `/orders/{id}` | Owner, Cashier | 200 |
| Orders | PUT | `/orders/{id}/items` | Cashier | 200 |
| Orders | PUT | `/orders/{id}/promo` | Cashier | 200 |
| Orders | DELETE | `/orders/{id}/promo` | Cashier | 200 |
| Orders | POST | `/orders/{id}/checkout` | Cashier | 200 |
| Orders | POST | `/orders/{id}/cancel` | Cashier | 200 |
| Payments | GET | `/orders/{id}/payments` | Owner, Cashier | 200 |
| Payments | POST | `/orders/{id}/payments` | Cashier | 201 |
| Payments | POST | `/payments/{id}/sync` | Cashier | 200 |
| Payments | POST | `/payments/midtrans/notification` | Public (signature Midtrans) | 200 |

---

### 4.1 Auth

#### `POST /auth/login`
**Akses:** Public. Dibatasi 5 percobaan gagal per menit untuk setiap kombinasi IP + username.

**Request body**
```json
{
  "username": "kasir.budi",
  "password": "rahasia123"
}
```

**Response 200**
```json
{
  "success": true,
  "message": "Login berhasil",
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "token_type": "Bearer",
    "expires_at": "2026-10-27T20:30:00Z",
    "user": {
      "id": "0192f0a1-7b3c-7c1e-9f2a-1c2d3e4f5a6b",
      "full_name": "Budi Santoso",
      "username": "kasir.budi",
      "role": "CASHIER"
    }
  }
}
```

**Error**
| HTTP | Kapan |
|---|---|
| 401 | Username tidak ada atau password salah. `message`: `"Username atau password salah"`. Pesan sengaja dibuat sama untuk kedua kasus |
| 401 | Akun dinonaktifkan. `message`: `"Akun Anda dinonaktifkan. Hubungi Owner."` |
| 422 | `errors.username` / `errors.password` kosong |
| 429 | Terlalu banyak percobaan gagal. `message`: `"Terlalu banyak percobaan login. Coba lagi dalam 1 menit."` |

#### `POST /auth/logout`
**Akses:** Owner, Cashier. Menaikkan `token_version`, sehingga **semua** sesi user ini di perangkat mana pun ikut keluar.

**Request body:** tidak ada.

**Response 200**
```json
{ "success": true, "message": "Logout berhasil", "data": null }
```

#### `GET /auth/me`
**Akses:** Owner, Cashier.

**Response 200**
```json
{
  "success": true,
  "message": "Data user berhasil diambil",
  "data": {
    "id": "0192f0a1-7b3c-7c1e-9f2a-1c2d3e4f5a6b",
    "full_name": "Budi Santoso",
    "username": "kasir.budi",
    "role": "CASHIER",
    "status": "ACTIVE",
    "last_login_at": "2026-10-27T01:00:00Z",
    "open_shift_id": "0192f0b2-1111-7aaa-8bbb-ccccdddd0001"
  }
}
```
`open_shift_id` bernilai `null` untuk Owner atau untuk Cashier yang belum membuka shift. Client memakai nilai ini untuk menentukan layar awal (buka shift atau layar kasir).

#### `PUT /auth/password`
**Akses:** Owner, Cashier. Mengganti password sendiri. Semua token lama tidak berlaku, dan token baru dikembalikan di response.

**Request body**
```json
{
  "current_password": "rahasia123",
  "new_password": "rahasiaBaru456"
}
```

**Response 200:** `data` sama dengan response `POST /auth/login`, dengan `message`: `"Password berhasil diubah"`.

**Error**
| HTTP | Kapan |
|---|---|
| 422 | `errors.current_password`: password lama salah |
| 422 | `errors.new_password`: kurang dari 8 karakter atau sama dengan password lama |

---

### 4.2 Categories

**Objek Category**
```json
{
  "id": "0192f0c3-0001-7abc-8def-000000000001",
  "name": "Kopi",
  "sort_order": 1,
  "status": "ACTIVE",
  "product_count": 12,
  "deleted_at": null,
  "created_at": "2026-10-01T03:00:00Z",
  "updated_at": "2026-10-01T03:00:00Z"
}
```

#### `GET /categories`
**Akses:** Owner, Cashier. Cashier hanya menerima kategori `ACTIVE` yang belum dihapus, diurutkan berdasarkan `sort_order`, dan filter `status` diabaikan.

**Query params**
| Param | Tipe | Keterangan |
|---|---|---|
| `status` | `ACTIVE` \| `INACTIVE` | Opsional (khusus Owner) |
| `search` | string | Cari berdasarkan nama |
| `page`, `per_page` | int | Pagination |

**Response 200**
```json
{
  "success": true,
  "message": "Data kategori berhasil diambil",
  "data": [ <Category>, ... ],
  "meta": { "page": 1, "per_page": 20, "total_items": 6, "total_pages": 1 }
}
```

#### `GET /categories/{id}`
**Akses:** Owner.
**Response 200:** `{ "success": true, "message": "Detail kategori berhasil diambil", "data": <Category> }`
**Error:** 404 kategori tidak ditemukan.

#### `POST /categories`
**Akses:** Owner.

**Request body**
```json
{
  "name": "Non-Kopi",
  "sort_order": 2,
  "status": "ACTIVE"
}
```
`name` wajib (maks. 50 karakter). `sort_order` default `0`. `status` default `ACTIVE`.

**Response 201:** `{ "success": true, "message": "Kategori berhasil dibuat", "data": <Category> }`

**Error**
| HTTP | Kapan |
|---|---|
| 422 | `errors.name`: kosong, terlalu panjang, atau sudah dipakai kategori lain yang belum dihapus |
| 422 | `errors.status` / `errors.sort_order`: nilai tidak valid |

#### `PUT /categories/{id}`
**Akses:** Owner. Body sama dengan `POST`, semua field wajib dikirim.
**Response 200:** `{ "success": true, "message": "Kategori berhasil diperbarui", "data": <Category> }`
**Error:** 404 kategori tidak ditemukan. 422 sama seperti `POST`.

#### `DELETE /categories/{id}`
**Akses:** Owner. Soft delete.

**Response 200**
```json
{
  "success": true,
  "message": "Kategori berhasil dihapus",
  "data": { "id": "0192f0c3-0001-7abc-8def-000000000001", "deleted_at": "2026-10-27T08:30:00Z" }
}
```

**Error**
| HTTP | Kapan |
|---|---|
| 400 | Masih ada produk di kategori ini. `message`: `"Kategori tidak bisa dihapus karena masih memiliki 12 produk"` |
| 404 | Kategori tidak ada atau sudah dihapus |

---

### 4.3 Products

**Objek Product**
```json
{
  "id": "0192f0d4-0001-7abc-8def-000000000001",
  "category": { "id": "0192f0c3-0001-7abc-8def-000000000001", "name": "Kopi" },
  "sku": "KOP-001",
  "name": "Es Kopi Susu Aren",
  "description": "Espresso, susu segar, gula aren",
  "price": 2500000,
  "photo_url": "https://cdn.<domain>/products/0192f0d4-0001.webp",
  "status": "ACTIVE",
  "track_stock": false,
  "stock": 0,
  "min_stock": 0,
  "is_low_stock": false,
  "deleted_at": null,
  "created_at": "2026-10-01T03:00:00Z",
  "updated_at": "2026-10-20T03:00:00Z"
}
```
`is_low_stock` = `track_stock && stock <= min_stock` (dihitung server).

#### `GET /products`
**Akses:** Owner, Cashier. Cashier hanya menerima produk `ACTIVE` yang belum dihapus dengan kategori `ACTIVE`. Filter `status`, `deleted`, dan `low_stock` diabaikan untuk Cashier.

**Query params**
| Param | Tipe | Keterangan |
|---|---|---|
| `search` | string | Cari di nama dan SKU |
| `category_id` | UUID | |
| `status` | `ACTIVE` \| `INACTIVE` | Khusus Owner |
| `track_stock` | bool | |
| `low_stock` | bool | `true` = hanya produk yang stoknya menipis (khusus Owner) |
| `deleted` | bool | `true` = hanya produk yang sudah di-soft delete (khusus Owner, PRD 3.1) |
| `sort` | `name` \| `-name` \| `price` \| `-price` \| `created_at` \| `-created_at` | Default `name`. Awalan `-` berarti descending |
| `page`, `per_page` | int | Pagination |

**Response 200**
```json
{
  "success": true,
  "message": "Data produk berhasil diambil",
  "data": [ <Product>, ... ],
  "meta": { "page": 1, "per_page": 20, "total_items": 57, "total_pages": 3 }
}
```
**Error:** 422 jika nilai filter tidak valid (mis. `errors.sort`).

#### `GET /products/{id}`
**Akses:** Owner, Cashier (Cashier hanya untuk produk aktif).
**Response 200:** `{ "success": true, "message": "Detail produk berhasil diambil", "data": <Product> }`
**Error:** 404 produk tidak ditemukan.

#### `POST /products`
**Akses:** Owner. Foto di-upload terpisah lewat `POST /products/{id}/photo`.

**Request body**
```json
{
  "category_id": "0192f0c3-0001-7abc-8def-000000000001",
  "sku": "KUE-003",
  "name": "Croissant Butter",
  "description": null,
  "price": 2800000,
  "status": "ACTIVE",
  "track_stock": true,
  "initial_stock": 20,
  "min_stock": 5
}
```
- Wajib: `category_id`, `sku`, `name`, `price`.
- `price` harus integer ≥ 0 dan kelipatan 100 (rupiah bulat, lihat SCHEMA D-02).
- `initial_stock` (opsional, default `0`, hanya berlaku jika `track_stock = true`). Jika > 0, server otomatis mencatat `stock_movements` bertipe `IN` dengan catatan "Stok awal".

**Response 201:** `{ "success": true, "message": "Produk berhasil dibuat", "data": <Product> }`

**Error**
| HTTP | Kapan |
|---|---|
| 422 | `errors.sku`: kosong atau sudah dipakai produk lain yang belum dihapus |
| 422 | `errors.price`: kosong, negatif, atau bukan kelipatan 100 |
| 422 | `errors.category_id`: kosong atau kategori tidak ditemukan |
| 422 | `errors.<field>` lain yang tidak valid |

Contoh:
```json
{
  "success": false,
  "message": "Data yang dikirim tidak valid",
  "errors": {
    "sku": ["SKU KUE-003 sudah dipakai produk lain"],
    "price": ["Harga harus kelipatan 100 (rupiah bulat)"]
  }
}
```

#### `PUT /products/{id}`
**Akses:** Owner. Body sama dengan `POST`, tetapi **tanpa** `initial_stock`. Stok hanya bisa diubah lewat `POST /stock/movements`. Perubahan harga tidak memengaruhi transaksi lama (BR-06).
**Response 200:** `{ "success": true, "message": "Produk berhasil diperbarui", "data": <Product> }`
**Error:** 404 produk tidak ditemukan. 422 sama seperti `POST`.

#### `PATCH /products/{id}/status`
**Akses:** Owner.

**Request body**
```json
{ "status": "INACTIVE" }
```
**Response 200:** `{ "success": true, "message": "Status produk berhasil diperbarui", "data": <Product> }`
**Error:** 404 produk tidak ditemukan. 422 `errors.status` tidak valid.

#### `DELETE /products/{id}`
**Akses:** Owner. Soft delete. Data produk tetap tampil di detail transaksi lama.

**Response 200**
```json
{
  "success": true,
  "message": "Produk berhasil dihapus",
  "data": { "id": "0192f0d4-0001-7abc-8def-000000000001", "deleted_at": "2026-10-27T08:30:00Z" }
}
```
**Error:** 404 produk tidak ditemukan.

#### `POST /products/{id}/photo`
**Akses:** Owner. `Content-Type: multipart/form-data`. Foto lama diganti.

**Form field**
| Field | Tipe | Keterangan |
|---|---|---|
| `photo` | file | JPG/PNG/WebP, maks. 2 MB. Server memeriksa tipe file dari isinya, bukan dari ekstensi |

**Response 200**
```json
{
  "success": true,
  "message": "Foto produk berhasil diunggah",
  "data": {
    "id": "0192f0d4-0001-7abc-8def-000000000001",
    "photo_url": "https://cdn.<domain>/products/0192f0d4-0001.webp"
  }
}
```

**Error**
| HTTP | Kapan |
|---|---|
| 404 | Produk tidak ditemukan |
| 422 | `errors.photo`: tidak dikirim, ukuran > 2 MB, atau format bukan JPG/PNG/WebP |

#### `DELETE /products/{id}/photo`
**Akses:** Owner.
**Response 200:** `{ "success": true, "message": "Foto produk berhasil dihapus", "data": { "id": "...", "photo_url": null } }`
**Error:** 404 produk tidak ditemukan.

---

### 4.4 Stock

**Objek StockMovement**
```json
{
  "id": "0192f0e5-0001-7abc-8def-000000000001",
  "product": { "id": "0192f0d4-0003-...", "sku": "KUE-003", "name": "Croissant Butter" },
  "movement_type": "OUT_SALE",
  "quantity": -2,
  "stock_before": 18,
  "stock_after": 16,
  "transaction": { "id": "0192f100-...", "transaction_number": "TRX-20261027-0012" },
  "note": null,
  "is_oversold": false,
  "created_by": { "id": "0192f0a1-...", "full_name": "Budi Santoso" },
  "created_at": "2026-10-27T04:12:00Z"
}
```
`transaction` bernilai `null` untuk pergerakan manual.

#### `POST /stock/movements`
**Akses:** Owner. Hanya untuk pergerakan manual. `OUT_SALE` dan `RETURN_VOID` dibuat otomatis oleh sistem.

**Request body: stok masuk**
```json
{
  "product_id": "0192f0d4-0003-7abc-8def-000000000003",
  "movement_type": "IN",
  "quantity": 24,
  "note": "Kiriman pagi"
}
```

**Request body: waste**
```json
{
  "product_id": "0192f0d4-0003-7abc-8def-000000000003",
  "movement_type": "WASTE",
  "quantity": 3,
  "note": "Kedaluwarsa"
}
```

**Request body: penyesuaian (stock opname)**
```json
{
  "product_id": "0192f0d4-0003-7abc-8def-000000000003",
  "movement_type": "ADJUSTMENT",
  "actual_stock": 15,
  "note": "Opname akhir minggu"
}
```

| `movement_type` | Field jumlah | Aturan |
|---|---|---|
| `IN` | `quantity` > 0 | `note` opsional |
| `WASTE` | `quantity` > 0 | Server menyimpannya sebagai delta negatif. `note` wajib |
| `ADJUSTMENT` | `actual_stock` ≥ 0 | Hasil hitung fisik. Server menghitung delta = `actual_stock − stock`. `note` wajib |

**Response 201:** `{ "success": true, "message": "Pergerakan stok berhasil dicatat", "data": <StockMovement> }`

**Error**
| HTTP | Kapan |
|---|---|
| 422 | `errors.product_id`: produk tidak ditemukan, sudah dihapus, atau tidak melacak stok (`track_stock = false`) |
| 422 | `errors.movement_type`: bukan `IN`, `WASTE`, atau `ADJUSTMENT` |
| 422 | `errors.quantity` / `errors.actual_stock`: nilai tidak valid, atau delta `ADJUSTMENT` = 0 |
| 422 | `errors.note`: kosong untuk `WASTE`/`ADJUSTMENT` |

#### `GET /stock/movements`
**Akses:** Owner.

**Query params**
| Param | Tipe | Keterangan |
|---|---|---|
| `product_id` | UUID | Riwayat satu produk |
| `movement_type` | ENUM, boleh lebih dari satu dipisah koma | Mis. `IN,WASTE` |
| `start_date`, `end_date` | `YYYY-MM-DD` | Rentang tanggal |
| `page`, `per_page` | int | Diurutkan dari yang terbaru |

**Response 200**
```json
{
  "success": true,
  "message": "Data riwayat stok berhasil diambil",
  "data": [ <StockMovement>, ... ],
  "meta": { "page": 1, "per_page": 20, "total_items": 240, "total_pages": 12 }
}
```
**Error:** 422 `errors.start_date` / `errors.end_date` jika format salah atau `start_date` > `end_date`.

#### `GET /stock/alerts`
**Akses:** Owner. Menampilkan produk yang stoknya menipis dan pergerakan oversold (BR-11) yang perlu ditindaklanjuti.

**Response 200**
```json
{
  "success": true,
  "message": "Data peringatan stok berhasil diambil",
  "data": {
    "low_stock": [
      { "id": "0192f0d4-0003-...", "sku": "KUE-003", "name": "Croissant Butter", "stock": 4, "min_stock": 5 }
    ],
    "oversold": [
      {
        "movement_id": "0192f0e5-0099-...",
        "product": { "id": "0192f0d4-0007-...", "name": "Banana Bread" },
        "stock_after": -1,
        "transaction": { "id": "0192f100-...", "transaction_number": "TRX-20261027-0040" },
        "created_at": "2026-10-27T09:00:00Z"
      }
    ]
  }
}
```

---

### 4.5 Tables

**Objek Table**
```json
{
  "id": "0192f0f6-0001-7abc-8def-000000000001",
  "table_number": "A1",
  "capacity": 4,
  "occupancy_status": "OCCUPIED",
  "status": "ACTIVE",
  "active_order": { "id": "0192f100-...", "transaction_number": "TRX-20261027-0012" },
  "deleted_at": null,
  "created_at": "2026-10-01T03:00:00Z",
  "updated_at": "2026-10-27T04:00:00Z"
}
```
`active_order` bernilai `null` jika meja `AVAILABLE`. Kasir memakainya untuk membuka kembali order di meja tersebut.

#### `GET /tables`
**Akses:** Owner, Cashier. Cashier hanya menerima meja `ACTIVE` yang belum dihapus.

**Query params:** `status` (khusus Owner), `occupancy_status`, `page`, `per_page`. Diurutkan berdasarkan `table_number`.

**Response 200**
```json
{
  "success": true,
  "message": "Data meja berhasil diambil",
  "data": [ <Table>, ... ],
  "meta": { "page": 1, "per_page": 20, "total_items": 15, "total_pages": 1 }
}
```

#### `GET /tables/{id}`
**Akses:** Owner.
**Response 200:** `{ "success": true, "message": "Detail meja berhasil diambil", "data": <Table> }`
**Error:** 404 meja tidak ditemukan.

#### `POST /tables`
**Akses:** Owner.

**Request body**
```json
{
  "table_number": "B3",
  "capacity": 2,
  "status": "ACTIVE"
}
```
**Response 201:** `{ "success": true, "message": "Meja berhasil dibuat", "data": <Table> }`

**Error**
| HTTP | Kapan |
|---|---|
| 422 | `errors.table_number`: kosong atau sudah dipakai meja lain yang belum dihapus |
| 422 | `errors.capacity`: kurang dari 1 |

#### `PUT /tables/{id}`
**Akses:** Owner. Body sama dengan `POST`. `occupancy_status` tidak bisa diubah manual karena dikelola oleh sistem.
**Response 200:** `{ "success": true, "message": "Meja berhasil diperbarui", "data": <Table> }`

**Error**
| HTTP | Kapan |
|---|---|
| 400 | Mengubah `status` ke `INACTIVE` saat meja sedang dipakai. `message`: `"Meja A1 sedang dipakai dan tidak bisa dinonaktifkan"` |
| 404 | Meja tidak ditemukan |
| 422 | Sama seperti `POST` |

#### `PATCH /tables/{id}/status`
**Akses:** Owner.

**Request body**
```json
{ "status": "INACTIVE" }
```
**Response 200:** `{ "success": true, "message": "Status meja berhasil diperbarui", "data": <Table> }`
**Error:** 400 meja sedang dipakai. 404 meja tidak ditemukan. 422 `errors.status` tidak valid.

#### `DELETE /tables/{id}`
**Akses:** Owner. Soft delete.
**Response 200:** `{ "success": true, "message": "Meja berhasil dihapus", "data": { "id": "...", "deleted_at": "2026-10-27T08:30:00Z" } }`
**Error:** 400 meja sedang dipakai. 404 meja tidak ditemukan.

---

### 4.6 Users (Cashier Management)

Endpoint ini hanya mengelola akun **Cashier**. Akun Owner dibuat lewat seeder/CLI saat instalasi. `password_hash` tidak pernah dikirim di response.

**Objek User**
```json
{
  "id": "0192f0a1-7b3c-7c1e-9f2a-1c2d3e4f5a6b",
  "full_name": "Budi Santoso",
  "username": "kasir.budi",
  "role": "CASHIER",
  "status": "ACTIVE",
  "has_open_shift": true,
  "last_login_at": "2026-10-27T01:00:00Z",
  "created_at": "2026-09-01T03:00:00Z",
  "updated_at": "2026-10-27T01:00:00Z"
}
```

#### `GET /users`
**Akses:** Owner.
**Query params:** `search` (nama atau username), `status`, `page`, `per_page`.

**Response 200**
```json
{
  "success": true,
  "message": "Data cashier berhasil diambil",
  "data": [ <User>, ... ],
  "meta": { "page": 1, "per_page": 20, "total_items": 5, "total_pages": 1 }
}
```
Hanya berisi user dengan role `CASHIER`.

#### `GET /users/{id}`
**Akses:** Owner.
**Response 200:** `{ "success": true, "message": "Detail cashier berhasil diambil", "data": <User> }`
**Error:** 404 cashier tidak ditemukan.

#### `POST /users`
**Akses:** Owner. Role selalu `CASHIER`.

**Request body**
```json
{
  "full_name": "Sari Dewi",
  "username": "kasir.sari",
  "password": "passwordAwal1"
}
```
`username`: 3–50 karakter, huruf kecil, angka, titik, atau underscore. `password`: minimal 8 karakter.

**Response 201:** `{ "success": true, "message": "Cashier berhasil dibuat", "data": <User> }`

**Error**
| HTTP | Kapan |
|---|---|
| 422 | `errors.username`: format salah atau sudah dipakai |
| 422 | `errors.password`: kurang dari 8 karakter |
| 422 | `errors.full_name`: kosong |

#### `PUT /users/{id}`
**Akses:** Owner.

**Request body**
```json
{
  "full_name": "Sari Dewi Lestari",
  "username": "kasir.sari"
}
```
**Response 200:** `{ "success": true, "message": "Cashier berhasil diperbarui", "data": <User> }`
**Error:** 404 cashier tidak ditemukan. 422 `errors.username` / `errors.full_name`.

#### `PATCH /users/{id}/status`
**Akses:** Owner. Menonaktifkan user akan menaikkan `token_version`, sehingga sesi user tersebut langsung berakhir.

**Request body**
```json
{ "status": "INACTIVE" }
```
**Response 200:** `{ "success": true, "message": "Status cashier berhasil diperbarui", "data": <User> }`

**Error**
| HTTP | Kapan |
|---|---|
| 400 | Cashier masih punya shift terbuka (PRD 3.5). `message`: `"Cashier Budi Santoso masih memiliki shift terbuka"` |
| 404 | Cashier tidak ditemukan |
| 422 | `errors.status`: nilai tidak valid |

#### `POST /users/{id}/reset-password`
**Akses:** Owner. Semua sesi cashier tersebut ikut berakhir.

**Request body**
```json
{ "new_password": "passwordBaru9" }
```
**Response 200:** `{ "success": true, "message": "Password cashier berhasil direset", "data": null }`
**Error:** 404 cashier tidak ditemukan. 422 `errors.new_password`.

---

### 4.7 Promos

**Objek Promo**
```json
{
  "id": "0192f107-0001-7abc-8def-000000000001",
  "name": "Happy Hour 20%",
  "code": "HAPPY20",
  "discount_type": "PERCENTAGE",
  "discount_percent": 20,
  "discount_amount": null,
  "max_discount": 2000000,
  "min_purchase": 5000000,
  "starts_at": "2026-10-01T07:00:00Z",
  "ends_at": "2026-12-31T16:59:59Z",
  "status": "ACTIVE",
  "is_currently_active": true,
  "usage_count": 134,
  "deleted_at": null,
  "created_at": "2026-09-28T03:00:00Z",
  "updated_at": "2026-09-28T03:00:00Z"
}
```
`is_currently_active` = `status = ACTIVE` **dan** waktu sekarang berada di antara `starts_at` dan `ends_at` (PRD 3.7).

#### `GET /promos`
**Akses:** Owner.
**Query params:** `status`, `discount_type`, `currently_active` (bool), `search`, `page`, `per_page`.

**Response 200**
```json
{
  "success": true,
  "message": "Data promo berhasil diambil",
  "data": [ <Promo>, ... ],
  "meta": { "page": 1, "per_page": 20, "total_items": 8, "total_pages": 1 }
}
```

#### `GET /promos/active`
**Akses:** Owner, Cashier. Berisi promo yang sedang aktif untuk ditampilkan di layar kasir. Tidak memakai pagination, sehingga tidak ada `meta`.

**Query params**
| Param | Tipe | Keterangan |
|---|---|---|
| `subtotal` | int (sen) | Opsional. Jika dikirim, server menghitung kelayakan dan estimasi potongan untuk setiap promo |

**Response 200**
```json
{
  "success": true,
  "message": "Data promo aktif berhasil diambil",
  "data": [
    {
      "id": "0192f107-0001-7abc-8def-000000000001",
      "name": "Happy Hour 20%",
      "code": "HAPPY20",
      "discount_type": "PERCENTAGE",
      "discount_percent": 20,
      "discount_amount": null,
      "max_discount": 2000000,
      "min_purchase": 5000000,
      "ends_at": "2026-12-31T16:59:59Z",
      "eligible": true,
      "estimated_discount": 1300000
    }
  ]
}
```
`eligible` dan `estimated_discount` bernilai `null` jika `subtotal` tidak dikirim.

**Error:** 422 `errors.subtotal` jika bukan integer ≥ 0.

#### `GET /promos/{id}`
**Akses:** Owner.
**Response 200:** `{ "success": true, "message": "Detail promo berhasil diambil", "data": <Promo> }`
**Error:** 404 promo tidak ditemukan.

#### `POST /promos`
**Akses:** Owner.

**Request body: persentase**
```json
{
  "name": "Happy Hour 20%",
  "code": "HAPPY20",
  "discount_type": "PERCENTAGE",
  "discount_percent": 20,
  "max_discount": 2000000,
  "min_purchase": 5000000,
  "starts_at": "2026-10-01T07:00:00Z",
  "ends_at": "2026-12-31T16:59:59Z",
  "status": "ACTIVE"
}
```

**Request body: nominal**
```json
{
  "name": "Potongan 10rb",
  "code": null,
  "discount_type": "FIXED",
  "discount_amount": 1000000,
  "min_purchase": 7500000,
  "starts_at": "2026-11-01T00:00:00Z",
  "ends_at": "2026-11-30T16:59:59Z",
  "status": "ACTIVE"
}
```

Validasi (sesuai SCHEMA `chk_promo_value`):
- `PERCENTAGE`: `discount_percent` 1–100. `discount_amount` harus `null`. `max_discount` opsional (> 0).
- `FIXED`: `discount_amount` > 0. `discount_percent` dan `max_discount` harus `null`.
- Semua nilai uang kelipatan 100. `ends_at` > `starts_at`. `ends_at` tidak boleh melewati tahun 2037 (SCHEMA D-03).

**Response 201:** `{ "success": true, "message": "Promo berhasil dibuat", "data": <Promo> }`

**Error**
| HTTP | Kapan |
|---|---|
| 422 | `errors.code`: sudah dipakai promo lain yang belum dihapus |
| 422 | `errors.discount_percent` / `errors.discount_amount` / `errors.max_discount`: tidak sesuai `discount_type` |
| 422 | `errors.ends_at`: tidak setelah `starts_at` atau melewati 2037 |
| 422 | `errors.<field>` lain yang tidak valid |

#### `PUT /promos/{id}`
**Akses:** Owner. Body sama dengan `POST`. Perubahan tidak memengaruhi transaksi yang sudah memakai promo ini (snapshot).
**Response 200:** `{ "success": true, "message": "Promo berhasil diperbarui", "data": <Promo> }`
**Error:** 404 promo tidak ditemukan. 422 sama seperti `POST`.

#### `PATCH /promos/{id}/status`
**Akses:** Owner.

**Request body**
```json
{ "status": "INACTIVE" }
```
**Response 200:** `{ "success": true, "message": "Status promo berhasil diperbarui", "data": <Promo> }`
**Error:** 404 promo tidak ditemukan. 422 `errors.status` tidak valid.

#### `DELETE /promos/{id}`
**Akses:** Owner. Soft delete, hanya untuk promo yang **belum pernah dipakai**. Promo yang sudah dipakai harus dinonaktifkan lewat `PATCH /promos/{id}/status` (PRD 3.7).
**Response 200:** `{ "success": true, "message": "Promo berhasil dihapus", "data": { "id": "...", "deleted_at": "2026-10-27T08:30:00Z" } }`

**Error**
| HTTP | Kapan |
|---|---|
| 400 | Promo sudah pernah dipakai. `message`: `"Promo sudah dipakai di 134 transaksi dan hanya bisa dinonaktifkan"` |
| 404 | Promo tidak ditemukan |

---

### 4.8 Reports

Semua laporan hanya menghitung transaksi berstatus `PAID`, dikelompokkan berdasarkan `paid_at` dalam zona waktu `Asia/Jakarta` (PRD 3.6).

**Query params periode (berlaku untuk semua endpoint report)**
| Param | Tipe | Keterangan |
|---|---|---|
| `period` | `today` \| `last_7_days` \| `last_30_days` \| `this_month` \| `custom` | Default `today` |
| `start_date`, `end_date` | `YYYY-MM-DD` | Wajib jika `period=custom`. Maksimal rentang 366 hari |

**Error periode (berlaku untuk semua endpoint report):** 422 dengan `errors.period`, `errors.start_date`, atau `errors.end_date` jika tanggal tidak valid, `start_date` > `end_date`, atau rentang > 366 hari.

#### `GET /reports/summary`
**Akses:** Owner.

**Response 200**
```json
{
  "success": true,
  "message": "Ringkasan laporan berhasil diambil",
  "data": {
    "period": { "start_date": "2026-10-01", "end_date": "2026-10-27", "timezone": "Asia/Jakarta" },
    "gross_sales": 4850000000,
    "total_discount": 125000000,
    "net_sales": 4725000000,
    "transaction_count": 1890,
    "average_transaction_value": 2500000,
    "by_payment_method": {
      "CASH": { "transaction_count": 610, "net_sales": 1480000000 },
      "MIDTRANS": { "transaction_count": 1280, "net_sales": 3245000000 }
    },
    "stock_warning_count": 2
  }
}
```
`gross_sales` = Σ `subtotal`. `net_sales` = Σ `total`. `average_transaction_value` = `net_sales / transaction_count`, dibulatkan ke bawah ke rupiah.

#### `GET /reports/revenue`
**Akses:** Owner. Data tren untuk grafik.

**Query params tambahan**
| Param | Tipe | Keterangan |
|---|---|---|
| `granularity` | `day` \| `week` \| `month` | Default `day`. Minggu dimulai hari Senin (ISO 8601) |

**Response 200**
```json
{
  "success": true,
  "message": "Data revenue berhasil diambil",
  "data": {
    "granularity": "day",
    "period": { "start_date": "2026-10-21", "end_date": "2026-10-27", "timezone": "Asia/Jakarta" },
    "series": [
      { "bucket_start": "2026-10-21", "gross_sales": 182000000, "total_discount": 4500000, "net_sales": 177500000, "transaction_count": 71 },
      { "bucket_start": "2026-10-22", "gross_sales": 0, "total_discount": 0, "net_sales": 0, "transaction_count": 0 }
    ]
  }
}
```
Bucket tanpa transaksi tetap dikirim dengan nilai `0` agar grafik tidak bolong.

**Error:** error periode, ditambah 422 `errors.granularity`.

#### `GET /reports/top-products`
**Akses:** Owner.

**Query params tambahan**
| Param | Tipe | Keterangan |
|---|---|---|
| `sort_by` | `quantity` \| `revenue` | Default `quantity` |
| `category_id` | UUID | Opsional |
| `limit` | int | Default `10`, maksimal `50` |

**Response 200**
```json
{
  "success": true,
  "message": "Data produk terlaris berhasil diambil",
  "data": [
    {
      "rank": 1,
      "product_id": "0192f0d4-0001-7abc-8def-000000000001",
      "product_name": "Es Kopi Susu Aren",
      "category_name": "Kopi",
      "quantity_sold": 642,
      "revenue": 1605000000,
      "is_deleted": false
    }
  ]
}
```
`revenue` = Σ `line_total` sebelum diskon. Diskon berlaku di tingkat order, jadi tidak dibagi ke masing-masing produk.

**Error:** error periode, ditambah 422 `errors.sort_by` / `errors.limit`.

#### `GET /reports/cashiers`
**Akses:** Owner.

**Response 200**
```json
{
  "success": true,
  "message": "Data laporan per cashier berhasil diambil",
  "data": [
    {
      "cashier_id": "0192f0a1-7b3c-7c1e-9f2a-1c2d3e4f5a6b",
      "full_name": "Budi Santoso",
      "transaction_count": 802,
      "gross_sales": 2050000000,
      "total_discount": 51000000,
      "net_sales": 1999000000,
      "shift_count": 22,
      "total_cash_difference": -1500000
    }
  ]
}
```

#### `GET /reports/export/{report_type}`
**Akses:** Owner. Menggunakan query params periode yang sama.

**Path param `report_type`**
| Nilai | Isi |
|---|---|
| `transactions` | Satu baris per transaksi |
| `transaction-items` | Satu baris per item transaksi |
| `products` | Rekap penjualan per produk |
| `cashiers` | Rekap per cashier |
| `shifts` | Rekap shift |
| `stock-movements` | Riwayat pergerakan stok. Menerima filter tambahan `product_id` dan `movement_type` |

Khusus `transactions` dan `transaction-items`, export juga menerima filter `status` (default `PAID`) untuk keperluan audit.

**Response 200 (pengecualian format standar: body berupa file CSV, bukan JSON)**
```
HTTP/1.1 200 OK
Content-Type: text/csv; charset=utf-8
Content-Disposition: attachment; filename="transactions_2026-10-01_2026-10-27.csv"
Transfer-Encoding: chunked

﻿transaction_number,paid_at,cashier,order_type,table,subtotal,discount,total,payment_method,status
TRX-20261027-0012,2026-10-27 11:12:05,Budi Santoso,DINE_IN,A1,53000,5300,47700,MIDTRANS,PAID
```
- UTF-8 dengan BOM, pemisah koma, dan baris header (PRD 3.8). Response dikirim secara streaming.
- **Nilai uang di CSV ditulis dalam rupiah**, bukan sen, karena file ini dibuka manusia di Excel. Waktu ditulis dalam `Asia/Jakarta`.
- Semua validasi dilakukan **sebelum** streaming dimulai, sehingga error tetap dikembalikan dalam format JSON standar.

**Error:** 404 jika `report_type` tidak dikenal (`message`: `"Jenis laporan tidak ditemukan"`), dan error periode di atas.

---

### 4.9 Shifts

**Objek Shift**
```json
{
  "id": "0192f0b2-1111-7aaa-8bbb-ccccdddd0001",
  "cashier": { "id": "0192f0a1-7b3c-7c1e-9f2a-1c2d3e4f5a6b", "full_name": "Budi Santoso" },
  "status": "CLOSED",
  "opened_at": "2026-10-27T00:00:00Z",
  "closed_at": "2026-10-27T09:05:00Z",
  "opening_cash": 50000000,
  "recap": {
    "total_transactions": 84,
    "total_sales": 315000000,
    "total_discount": 8000000,
    "total_cash_sales": 98000000,
    "total_non_cash_sales": 217000000,
    "expected_cash": 148000000,
    "actual_cash": 147500000,
    "cash_difference": -500000
  },
  "closing_note": "Kurang 5rb, kemungkinan salah kembalian",
  "created_at": "2026-10-27T00:00:00Z",
  "updated_at": "2026-10-27T09:05:00Z"
}
```
`recap` dan `closing_note` bernilai `null` selama shift masih `OPEN`.

#### `POST /shifts/open`
**Akses:** Cashier.

**Request body**
```json
{ "opening_cash": 50000000 }
```
**Response 201:** `{ "success": true, "message": "Shift berhasil dibuka", "data": <Shift> }` (status `OPEN`)

**Error**
| HTTP | Kapan |
|---|---|
| 400 | Cashier sudah punya shift terbuka. `message`: `"Anda masih memiliki shift yang terbuka"`. Client memanggil `GET /shifts/current` untuk melanjutkan shift tersebut |
| 422 | `errors.opening_cash`: kosong, negatif, atau bukan kelipatan 100 |

#### `GET /shifts/current`
**Akses:** Cashier.

**Response 200: ada shift terbuka**
```json
{ "success": true, "message": "Shift aktif berhasil diambil", "data": <Shift> }
```

**Response 200: belum ada shift terbuka**
```json
{ "success": true, "message": "Tidak ada shift yang terbuka", "data": null }
```

#### `GET /shifts/current/summary`
**Akses:** Cashier. Pratinjau rekap sebelum shift ditutup, dihitung secara real-time. Belum ada data yang disimpan.

**Response 200**
```json
{
  "success": true,
  "message": "Ringkasan shift berhasil diambil",
  "data": {
    "shift_id": "0192f0b2-1111-7aaa-8bbb-ccccdddd0001",
    "opened_at": "2026-10-27T00:00:00Z",
    "opening_cash": 50000000,
    "total_transactions": 84,
    "total_sales": 315000000,
    "total_discount": 8000000,
    "total_cash_sales": 98000000,
    "total_non_cash_sales": 217000000,
    "expected_cash": 148000000,
    "unfinished_orders": [
      { "id": "0192f100-...", "transaction_number": "TRX-20261027-0083", "status": "PENDING", "total": 4500000 }
    ],
    "can_close": false
  }
}
```

**Error:** 400 jika belum ada shift terbuka (`message`: `"Anda belum membuka shift"`).

#### `POST /shifts/current/close`
**Akses:** Cashier. Rekap dihitung ulang oleh server di dalam DB transaction lalu disimpan secara permanen (BR-15, BR-16).

**Request body**
```json
{
  "actual_cash": 147500000,
  "closing_note": "Kurang 5rb, kemungkinan salah kembalian"
}
```
`closing_note` wajib diisi jika `actual_cash ≠ expected_cash`.

**Response 200:** `{ "success": true, "message": "Shift berhasil ditutup", "data": <Shift> }` (status `CLOSED`, `recap` terisi)

**Error**
| HTTP | Kapan |
|---|---|
| 400 | Belum ada shift terbuka. `message`: `"Anda belum membuka shift"` |
| 400 | Masih ada order `PENDING` atau `FAILED`. `message`: `"Masih ada 1 order yang belum selesai. Selesaikan atau batalkan order tersebut sebelum menutup shift"`. Daftar ordernya bisa diambil dari `GET /shifts/current/summary` |
| 422 | `errors.actual_cash`: kosong, negatif, atau bukan kelipatan 100 |
| 422 | `errors.closing_note`: kosong padahal ada selisih kas |

#### `GET /shifts`
**Akses:** Owner.
**Query params:** `cashier_id`, `status`, `start_date`, `end_date` (berdasarkan `opened_at`), `page`, `per_page`.

**Response 200**
```json
{
  "success": true,
  "message": "Data shift berhasil diambil",
  "data": [ <Shift>, ... ],
  "meta": { "page": 1, "per_page": 20, "total_items": 64, "total_pages": 4 }
}
```
**Error:** 422 jika filter tanggal tidak valid.

#### `GET /shifts/{id}`
**Akses:** Owner.
**Response 200:** `{ "success": true, "message": "Detail shift berhasil diambil", "data": <Shift> }`
**Error:** 404 shift tidak ditemukan.

---

### 4.10 Orders

"Order" di API sama dengan tabel `transactions` di database.

**Objek Order**
```json
{
  "id": "0192f100-0012-7abc-8def-000000000012",
  "transaction_number": "TRX-20261027-0012",
  "shift_id": "0192f0b2-1111-7aaa-8bbb-ccccdddd0001",
  "cashier": { "id": "0192f0a1-7b3c-7c1e-9f2a-1c2d3e4f5a6b", "full_name": "Budi Santoso" },
  "order_type": "DINE_IN",
  "table": { "id": "0192f0f6-0001-7abc-8def-000000000001", "table_number": "A1" },
  "status": "PENDING",
  "is_locked": false,
  "items": [
    {
      "id": "0192f101-0001-...",
      "product_id": "0192f0d4-0001-7abc-8def-000000000001",
      "product_name": "Es Kopi Susu Aren",
      "product_sku": "KOP-001",
      "category_name": "Kopi",
      "unit_price": 2500000,
      "quantity": 2,
      "line_total": 5000000,
      "note": "less sugar"
    },
    {
      "id": "0192f101-0002-...",
      "product_id": "0192f0d4-0003-7abc-8def-000000000003",
      "product_name": "Croissant Butter",
      "product_sku": "KUE-003",
      "category_name": "Pastry",
      "unit_price": 2800000,
      "quantity": 1,
      "line_total": 2800000,
      "note": null
    }
  ],
  "subtotal": 7800000,
  "discount_amount": 1560000,
  "total": 6240000,
  "promo": {
    "id": "0192f107-0001-7abc-8def-000000000001",
    "name": "Happy Hour 20%",
    "code": "HAPPY20",
    "discount_type": "PERCENTAGE",
    "discount_percent": 20,
    "discount_amount": null,
    "max_discount": 2000000,
    "min_purchase": 5000000
  },
  "payment_method": null,
  "has_stock_warning": false,
  "checked_out_at": null,
  "paid_at": null,
  "cancelled_at": null,
  "cancel_reason": null,
  "created_at": "2026-10-27T04:00:00Z",
  "updated_at": "2026-10-27T04:02:00Z"
}
```
- `is_locked` = `checked_out_at != null` (BR-08).
- `promo` diambil dari `promo_snapshot`, bukan dari data promo terbaru.
- `table` bernilai `null` untuk `TAKE_AWAY`.

**Aturan perhitungan (dilakukan di server, PRD 4.2 & 4.3):**
`line_total = unit_price × quantity` → `subtotal = Σ line_total` → diskon persentase = `floor(subtotal × percent / 100)` dibulatkan ke bawah ke kelipatan 100 sen (rupiah bulat), lalu dibatasi `max_discount`. Diskon nominal dibatasi agar tidak melebihi `subtotal` → `total = subtotal − discount_amount`.

#### `POST /orders`
**Akses:** Cashier dengan shift terbuka.

**Request body**
```json
{
  "order_type": "DINE_IN",
  "table_id": "0192f0f6-0001-7abc-8def-000000000001",
  "items": [
    { "product_id": "0192f0d4-0001-7abc-8def-000000000001", "quantity": 2, "note": "less sugar" },
    { "product_id": "0192f0d4-0003-7abc-8def-000000000003", "quantity": 1, "note": null }
  ],
  "promo_id": "0192f107-0001-7abc-8def-000000000001"
}
```
- `table_id` wajib untuk `DINE_IN` dan harus `null` untuk `TAKE_AWAY`.
- `items` minimal 1. `quantity` ≥ 1. Produk yang sama boleh muncul lebih dari sekali dengan `note` yang berbeda.
- `promo_id` opsional.
- Harga, nama, dan total **selalu dihitung server**. Field harga atau total dari client diabaikan.
- Meja otomatis berubah menjadi `OCCUPIED`.

**Response 201:** `{ "success": true, "message": "Order berhasil dibuat", "data": <Order> }` (status `PENDING`, `is_locked: false`)

**Error**
| HTTP | Kapan |
|---|---|
| 400 | Cashier belum membuka shift (BR-14). `message`: `"Anda belum membuka shift. Buka shift terlebih dahulu."` |
| 422 | `errors.table_id`: wajib untuk `DINE_IN`, harus kosong untuk `TAKE_AWAY`, meja nonaktif, atau meja sedang dipakai order aktif lain |
| 422 | `errors.items`: kosong |
| 422 | `errors["items.N.product_id"]`: produk tidak ditemukan, nonaktif, atau sudah dihapus |
| 422 | `errors["items.N.quantity"]`: kurang dari 1 atau melebihi stok tersedia |
| 422 | `errors.promo_id`: promo tidak aktif, atau subtotal belum mencapai `min_purchase` |
| 422 | `errors.order_type`: nilai tidak valid |

Contoh error stok dan meja:
```json
{
  "success": false,
  "message": "Data yang dikirim tidak valid",
  "errors": {
    "table_id": ["Meja A1 sedang dipakai order TRX-20261027-0009"],
    "items.1.quantity": ["Stok Croissant Butter tidak cukup, tersedia 1"]
  }
}
```

Contoh error promo:
```json
{
  "success": false,
  "message": "Data yang dikirim tidak valid",
  "errors": {
    "promo_id": ["Minimum belanja untuk promo Happy Hour 20% adalah Rp 50.000"]
  }
}
```

#### `GET /orders`
**Akses:** Owner, Cashier.
- **Cashier:** hanya menerima order dari shift terbukanya sendiri (PRD 4.5). Filter `cashier_id`, `shift_id`, dan tanggal diabaikan. Jika belum ada shift terbuka, response berupa 400 (`message`: `"Anda belum membuka shift"`).
- **Owner:** semua order, dengan semua filter tersedia.

**Query params**
| Param | Tipe | Keterangan |
|---|---|---|
| `status` | ENUM, boleh lebih dari satu dipisah koma | Mis. `PENDING,FAILED` |
| `order_type` | `DINE_IN` \| `TAKE_AWAY` | |
| `table_id` | UUID | |
| `search` | string | Cari berdasarkan `transaction_number` |
| `cashier_id`, `shift_id` | UUID | Khusus Owner |
| `start_date`, `end_date` | `YYYY-MM-DD` | Berdasarkan `created_at` (khusus Owner) |
| `page`, `per_page` | int | Diurutkan dari yang terbaru |

**Response 200:** list order ringkas (tanpa `items`):
```json
{
  "success": true,
  "message": "Data order berhasil diambil",
  "data": [
    {
      "id": "0192f100-0012-7abc-8def-000000000012",
      "transaction_number": "TRX-20261027-0012",
      "order_type": "DINE_IN",
      "table": { "id": "0192f0f6-0001-...", "table_number": "A1" },
      "status": "PAID",
      "is_locked": true,
      "item_count": 3,
      "total": 6240000,
      "payment_method": "MIDTRANS",
      "cashier": { "id": "0192f0a1-...", "full_name": "Budi Santoso" },
      "created_at": "2026-10-27T04:00:00Z",
      "paid_at": "2026-10-27T04:05:12Z"
    }
  ],
  "meta": { "page": 1, "per_page": 20, "total_items": 84, "total_pages": 5 }
}
```
**Error:** 400 belum ada shift terbuka (Cashier). 422 jika nilai filter tidak valid.

#### `GET /orders/{id}`
**Akses:** Owner (semua order) atau Cashier (hanya order di shift terbukanya). Response ini juga dipakai untuk tampilan struk.
**Response 200:** `{ "success": true, "message": "Detail order berhasil diambil", "data": <Order> }`
**Error:** 404 order tidak ditemukan. Status ini juga dipakai saat Cashier mengakses order cashier lain atau order shift lain, agar keberadaan order tersebut tidak terungkap.

#### `PUT /orders/{id}/items`
**Akses:** Cashier pemilik order. Mengganti **seluruh** daftar item, karena keranjang dikelola client. Hanya bisa dilakukan sebelum checkout. Jika order punya promo, promo divalidasi ulang terhadap subtotal baru.

**Request body**
```json
{
  "items": [
    { "product_id": "0192f0d4-0001-7abc-8def-000000000001", "quantity": 3, "note": "less sugar" }
  ]
}
```
**Response 200:** `{ "success": true, "message": "Item order berhasil diperbarui", "data": <Order> }`

**Error**
| HTTP | Kapan |
|---|---|
| 400 | Order sudah checkout (BR-08). `message`: `"Order sudah checkout dan tidak bisa diubah. Batalkan order lalu buat order baru."` |
| 400 | Status order bukan `PENDING` (mis. sudah `CANCELLED`) |
| 404 | Order tidak ditemukan atau bukan milik cashier |
| 422 | `errors.items`, `errors["items.N.product_id"]`, `errors["items.N.quantity"]`: sama seperti `POST /orders` |
| 422 | `errors.items`: subtotal baru di bawah `min_purchase` promo yang terpasang. Item **tidak** disimpan, kasir harus melepas promo terlebih dahulu |

#### `PUT /orders/{id}/promo`
**Akses:** Cashier pemilik order. Memasang promo. Jika order sudah punya promo, promo lama **diganti** (BR-17).

**Request body**
```json
{ "promo_id": "0192f107-0001-7abc-8def-000000000001" }
```
**Response 200:** `{ "success": true, "message": "Promo berhasil diterapkan", "data": <Order> }`

**Error**
| HTTP | Kapan |
|---|---|
| 400 | Order sudah checkout |
| 404 | Order tidak ditemukan atau bukan milik cashier |
| 422 | `errors.promo_id`: promo tidak ditemukan, tidak aktif saat ini, atau subtotal belum mencapai `min_purchase` |

#### `DELETE /orders/{id}/promo`
**Akses:** Cashier pemilik order. Melepas promo.
**Response 200:** `{ "success": true, "message": "Promo berhasil dilepas", "data": <Order> }` (dengan `promo: null`, `discount_amount: 0`)
**Error:** 400 order sudah checkout. 404 order tidak ditemukan.

#### `POST /orders/{id}/checkout`
**Akses:** Cashier pemilik order. Mengunci order (`checked_out_at` diisi) lalu membuat percobaan pembayaran pertama. Sebelum itu, server memvalidasi ulang produk, stok, dan promo (PRD 4.3 & 4.4).

**Request body: Midtrans**
```json
{ "payment_method": "MIDTRANS" }
```

**Response 200: Midtrans**
```json
{
  "success": true,
  "message": "Checkout berhasil, silakan lanjutkan pembayaran",
  "data": {
    "order": { "id": "0192f100-0012-...", "status": "PENDING", "is_locked": true, "total": 6240000, "checked_out_at": "2026-10-27T04:03:00Z" },
    "payment": {
      "id": "0192f110-0001-7abc-8def-000000000001",
      "attempt_number": 1,
      "method": "MIDTRANS",
      "order_id": "TRX-20261027-0012-1",
      "gross_amount": 6240000,
      "status": "PENDING",
      "snap_token": "66e4fa55-fdac-4ef9-91b5-733b97d1b862",
      "snap_redirect_url": "https://app.sandbox.midtrans.com/snap/v4/redirection/66e4fa55-...",
      "expires_at": "2026-10-27T04:18:00Z"
    }
  }
}
```
Client membuka Snap dengan `snap_token` (`window.snap.pay(token)`). Callback sukses dari Snap di sisi client **hanya untuk tampilan** dan bukan bukti lunas. Status `PAID` hanya datang dari webhook (BR-10, BR-22). Client memantau status dengan polling `GET /orders/{id}` setiap 3 detik, atau memanggil `POST /payments/{id}/sync`.

**Request body: Tunai**
```json
{ "payment_method": "CASH", "cash_received": 7000000 }
```

**Response 200: Tunai**
```json
{
  "success": true,
  "message": "Pembayaran tunai berhasil. Kembalian Rp 7.600",
  "data": {
    "order": { "id": "0192f100-0012-...", "status": "PAID", "is_locked": true, "total": 6240000, "paid_at": "2026-10-27T04:03:00Z" },
    "payment": {
      "id": "0192f110-0001-7abc-8def-000000000001",
      "attempt_number": 1,
      "method": "CASH",
      "order_id": null,
      "gross_amount": 6240000,
      "status": "SUCCESS",
      "cash_received": 7000000,
      "change_amount": 760000,
      "paid_at": "2026-10-27T04:03:00Z"
    }
  }
}
```
Pada pembayaran tunai, stok berkurang dan meja dibebaskan di DB transaction yang sama dengan perubahan status ke `PAID` (lihat catatan metode tunai di PRD).

**Idempotensi:** jika order sudah checkout dan masih punya percobaan Midtrans `PENDING` yang belum kedaluwarsa, endpoint mengembalikan percobaan yang sama (200) tanpa membuat token baru. Ini mencegah token ganda karena tombol checkout diklik dua kali.

**Error**
| HTTP | Kapan |
|---|---|
| 400 | Order sudah lunas. `message`: `"Order ini sudah dibayar"` |
| 400 | Order `CANCELLED`, atau sudah checkout dengan status `FAILED`/`EXPIRED` (gunakan `POST /orders/{id}/payments`) |
| 400 | Ada produk yang dinonaktifkan sejak order dibuat. `message`: `"Produk Banana Bread sudah tidak tersedia. Ubah item order terlebih dahulu."` |
| 400 | Stok tidak cukup. `message`: `"Stok Croissant Butter tidak cukup (diminta 3, tersedia 1). Ubah item order terlebih dahulu."` |
| 400 | Promo berakhir atau dinonaktifkan sejak dipasang. `message`: `"Promo Happy Hour 20% sudah tidak berlaku. Lepas atau ganti promo terlebih dahulu."` |
| 404 | Order tidak ditemukan atau bukan milik cashier |
| 422 | `errors.payment_method`: nilai tidak valid |
| 422 | `errors.cash_received`: kosong (untuk `CASH`) atau kurang dari `total` |
| 500 | Gagal membuat Snap token. `message`: `"Gagal terhubung ke Midtrans. Silakan coba lagi."` Order **tidak** dikunci, sehingga kasir bisa mencoba lagi |

#### `POST /orders/{id}/cancel`
**Akses:** Cashier pemilik order. Order bisa dibatalkan selama statusnya `PENDING` (sebelum atau sesudah checkout), `FAILED`, atau `EXPIRED`. Jika ada percobaan Midtrans yang masih `PENDING`, server membatalkannya dulu lewat Midtrans Cancel API. Meja dibebaskan (BR-21).

**Request body**
```json
{ "reason": "Pelanggan ingin mengubah pesanan" }
```
`reason` wajib diisi (maks. 255 karakter).

**Response 200:** `{ "success": true, "message": "Order berhasil dibatalkan", "data": <Order> }` (status `CANCELLED`)

**Error**
| HTTP | Kapan |
|---|---|
| 400 | Order sudah lunas, termasuk jika Midtrans ternyata sudah `settlement` saat pembatalan dicoba. Order otomatis diperbarui ke `PAID`. `message`: `"Order ini sudah dibayar dan tidak bisa dibatalkan"` |
| 400 | Order sudah `CANCELLED` |
| 404 | Order tidak ditemukan atau bukan milik cashier |
| 422 | `errors.reason`: kosong atau terlalu panjang |
| 500 | Midtrans Cancel API gagal. Status order tidak berubah |

---

### 4.11 Payments

**Objek Payment**
```json
{
  "id": "0192f110-0001-7abc-8def-000000000001",
  "order_id_ref": "0192f100-0012-7abc-8def-000000000012",
  "attempt_number": 1,
  "method": "MIDTRANS",
  "order_id": "TRX-20261027-0012-1",
  "gross_amount": 6240000,
  "status": "EXPIRED",
  "snap_token": "66e4fa55-fdac-4ef9-91b5-733b97d1b862",
  "snap_redirect_url": "https://app.sandbox.midtrans.com/snap/v4/redirection/66e4fa55-...",
  "midtrans_payment_type": null,
  "midtrans_status": "expire",
  "cash_received": null,
  "change_amount": null,
  "expires_at": "2026-10-27T04:18:00Z",
  "paid_at": null,
  "created_at": "2026-10-27T04:03:00Z",
  "updated_at": "2026-10-27T04:18:02Z"
}
```
- `order_id_ref`: UUID order (transaksi) di sistem kita.
- `order_id`: ID yang dikirim ke Midtrans, dengan format `<transaction_number>-<attempt_number>`.

#### `GET /orders/{id}/payments`
**Akses:** Owner, atau Cashier pemilik order.

**Response 200** (diurutkan berdasarkan `attempt_number`, tanpa pagination)
```json
{
  "success": true,
  "message": "Data pembayaran berhasil diambil",
  "data": [ <Payment>, ... ]
}
```
**Error:** 404 order tidak ditemukan.

#### `POST /orders/{id}/payments`
**Akses:** Cashier pemilik order. Membuat **percobaan pembayaran baru** untuk order yang sudah checkout. Endpoint ini dipakai saat pembayaran sebelumnya `FAILED`/`EXPIRED`, atau saat pelanggan ingin mengganti metode (mis. QRIS gagal lalu bayar tunai).
- Item dan promo tetap memakai snapshot yang terkunci saat checkout. Promo **tidak** divalidasi ulang di sini, jadi total tidak berubah.
- Jika masih ada percobaan Midtrans `PENDING`, server membatalkannya dulu lewat Midtrans Cancel API.
- Untuk order `DINE_IN` yang sudah `EXPIRED`, meja dikunci kembali. Jika meja sudah dipakai order lain, request ditolak.
- Order kembali berstatus `PENDING` (atau langsung `PAID` untuk tunai).

**Request body:** sama dengan `POST /orders/{id}/checkout`.
```json
{ "payment_method": "MIDTRANS" }
```

**Response 201:** format sama dengan response checkout (`data.order` + `data.payment`), dengan `attempt_number` yang bertambah dan `message`: `"Percobaan pembayaran baru berhasil dibuat"` (atau `"Pembayaran tunai berhasil. Kembalian Rp ..."` untuk tunai).

**Error**
| HTTP | Kapan |
|---|---|
| 400 | Order sudah lunas |
| 400 | Order belum checkout (gunakan `/checkout`) atau sudah `CANCELLED` |
| 400 | Meja order yang sudah `EXPIRED` kini dipakai order lain. `message`: `"Meja A1 sedang dipakai order lain. Batalkan order ini dan buat order baru."` |
| 400 | Stok tidak cukup. `message` menyebut produk dan sisa stok |
| 404 | Order tidak ditemukan atau bukan milik cashier |
| 422 | `errors.payment_method` / `errors.cash_received`: tidak valid |
| 500 | Gagal membatalkan percobaan lama atau membuat token baru di Midtrans |

#### `POST /payments/{id}/sync`
**Akses:** Cashier pemilik order. Menanyakan status terbaru ke Midtrans Get Status API, lalu menerapkan logika yang sama dengan webhook. Dipakai saat webhook terlambat atau pelanggan menunjukkan bukti bayar tetapi status masih `PENDING`. Data dari API resmi Midtrans memenuhi syarat BR-22 (PRD 4.4).

**Request body:** tidak ada.

**Response 200**
```json
{
  "success": true,
  "message": "Status pembayaran berhasil diperbarui",
  "data": {
    "payment": { "id": "0192f110-0001-...", "status": "SUCCESS", "midtrans_status": "settlement", "midtrans_payment_type": "qris", "paid_at": "2026-10-27T04:05:12Z" },
    "order": { "id": "0192f100-0012-...", "status": "PAID", "paid_at": "2026-10-27T04:05:12Z" },
    "changed": true
  }
}
```
Jika `changed: false` (status di Midtrans sama dengan yang tercatat), `message`: `"Status pembayaran belum berubah"`.

**Error**
| HTTP | Kapan |
|---|---|
| 400 | Payment bermetode `CASH`, sehingga tidak ada yang perlu disinkronkan |
| 404 | Payment tidak ditemukan atau bukan milik cashier |
| 500 | Midtrans tidak bisa dihubungi |

#### `POST /payments/midtrans/notification`
**Akses:** Public. Dipanggil oleh server Midtrans. Tidak memakai header `Authorization`. Keaslian dibuktikan dengan `signature_key`. URL ini didaftarkan sebagai *Payment Notification URL* di dashboard Midtrans.

**Request body** (dikirim Midtrans, contoh)
```json
{
  "transaction_time": "2026-10-27 11:05:10",
  "transaction_status": "settlement",
  "transaction_id": "9aed5972-5b6a-401e-894b-a32c91ed1a3a",
  "status_message": "midtrans payment notification",
  "status_code": "200",
  "signature_key": "d1c2b3a4...",
  "settlement_time": "2026-10-27 11:05:12",
  "payment_type": "qris",
  "order_id": "TRX-20261027-0012-1",
  "merchant_id": "G123456789",
  "gross_amount": "62400.00",
  "fraud_status": "accept",
  "currency": "IDR"
}
```

**Langkah pemrosesan**
1. Simpan payload mentah ke `payment_notifications`.
2. Verifikasi `signature_key == SHA512(order_id + status_code + gross_amount + server_key)` memakai string `gross_amount` apa adanya (BR-22).
3. Cari `payments` berdasarkan `order_id`. Pastikan `gross_amount` (rupiah) × 100 = `payments.gross_amount` (sen).
4. Petakan status sesuai PRD 4.4: `settlement`/`capture`+`accept` → `PAID`; `deny`/`failure` → `FAILED`; `expire` → `EXPIRED`; `cancel` → `CANCELLED`; `pending` → tetap `PENDING`.
5. Jika menjadi `PAID`: dalam satu DB transaction, ubah status payment dan order, kurangi stok (`SELECT ... FOR UPDATE`), catat `stock_movements`, lalu bebaskan meja. Notifikasi untuk status yang sudah tercatat diabaikan (idempotent, BR-23).

**Response:** body tidak dibaca Midtrans. Yang penting adalah status HTTP-nya, karena Midtrans akan **mengirim ulang** notifikasi jika menerima status selain 2xx.

| HTTP | `data.result` / `message` | Kapan |
|---|---|---|
| 200 | `APPLIED` | Status berhasil diterapkan |
| 200 | `DUPLICATE` | Status ini sudah pernah diproses |
| 200 | `IGNORED` | Notifikasi valid tetapi tidak mengubah apa pun (mis. `pending`, atau notifikasi untuk percobaan lama yang sudah dibatalkan) |
| 200 | `UNKNOWN_ORDER` | `order_id` tidak dikenal. Dicatat di log saja, dan 200 dikembalikan agar Midtrans tidak terus mengirim ulang |
| 401 | `"Signature tidak valid"` | Signature tidak cocok. Kemungkinan request palsu |
| 500 | `"Terjadi kesalahan pada server"` | Error database atau server. Midtrans akan mengirim ulang, dan pemrosesan ulang aman karena idempotent |

Contoh response 200:
```json
{ "success": true, "message": "Notifikasi diproses", "data": { "result": "APPLIED" } }
```

---

## Lampiran A — Alur Checkout

```
Kasir                    API Coffee POS                         Midtrans
  │ POST /orders            │                                       │
  │────────────────────────▶│ status PENDING, meja OCCUPIED         │
  │ PUT /orders/{id}/promo  │                                       │
  │────────────────────────▶│                                       │
  │ POST /orders/{id}/checkout (MIDTRANS)                           │
  │────────────────────────▶│ validasi ulang, kunci order           │
  │                         │──── create Snap transaction ─────────▶│
  │◀──── snap_token ────────│◀────────────── token ─────────────────│
  │ snap.pay(token) ─────────────────────── pelanggan bayar ───────▶│
  │                         │◀──── POST /payments/midtrans/notification
  │                         │ verifikasi signature → PAID,          │
  │                         │ kurangi stok, bebaskan meja           │
  │ GET /orders/{id} (poll) │                                       │
  │────────────────────────▶│ status PAID → tampilkan struk         │
```

## Lampiran B — Transisi Status Order

| Dari | Aksi | Ke |
|---|---|---|
| — | `POST /orders` | `PENDING` (belum terkunci) |
| `PENDING` (belum terkunci) | `POST /checkout` MIDTRANS | `PENDING` (terkunci) |
| `PENDING` (belum terkunci) | `POST /checkout` CASH | `PAID` |
| `PENDING` (terkunci) | Webhook `settlement` | `PAID` |
| `PENDING` (terkunci) | Webhook `deny`/`failure` | `FAILED` |
| `PENDING` (terkunci) | Webhook `expire` | `EXPIRED` (meja dibebaskan) |
| `FAILED` / `EXPIRED` | `POST /orders/{id}/payments` | `PENDING` (terkunci) atau `PAID` (tunai) |
| `PENDING` / `FAILED` / `EXPIRED` | `POST /orders/{id}/cancel` | `CANCELLED` (meja dibebaskan) |
| `PAID` / `CANCELLED` | — | Final |
