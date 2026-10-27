# PRD — Coffee POS

| Item | Keterangan |
|---|---|
| Produk | Coffee POS (Point of Sales untuk coffee shop) |
| Versi Dokumen | 1.0 |
| Tanggal | 27 Oktober 2026 |
| Tech Stack | Backend Go, database MySQL, payment gateway Midtrans Snap |
| Status | Draft |

---

## 1. Deskripsi Produk

### 1.1 Apa Ini
Coffee POS adalah aplikasi Point of Sales berbasis web untuk mengelola operasional penjualan harian coffee shop. Sistem ini mencakup pencatatan transaksi di kasir, pengelolaan produk dan stok, pengelolaan meja, shift kasir, promo, dan pembayaran non-tunai melalui Midtrans Snap. Pemilik usaha juga mendapat laporan penjualan.

### 1.2 Untuk Siapa
Coffee shop **skala menengah**, dengan ciri-ciri:
- Memiliki 1 outlet dengan 5–30 meja (dine-in) dan juga melayani take-away.
- Dioperasikan oleh 1 Owner dan 2–10 Cashier yang bekerja bergantian per shift.
- Menjual 30–200 item menu (minuman, makanan, snack) yang dikelompokkan per kategori.
- Volume transaksi sekitar 100–1.000 transaksi per hari.

### 1.3 Masalah yang Diselesaikan
- Pencatatan transaksi dan stok yang masih manual atau tersebar sehingga rawan selisih.
- Owner tidak punya data real-time soal revenue, produk terlaris, dan kinerja kasir.
- Selisih kas di akhir shift sulit dilacak karena tidak ada rekap modal awal dan penerimaan.
- Penerapan promo yang tidak konsisten antar kasir.

### 1.4 Tujuan
- Satu transaksi bisa diselesaikan kasir dalam waktu kurang dari 60 detik.
- Owner dapat melihat laporan revenue dan stok tanpa rekap manual.
- Setiap pergerakan stok dan uang tercatat dan dapat ditelusuri (audit trail).

---

## 2. User Roles

| Role | Deskripsi | Akses |
|---|---|---|
| **Owner** | Pemilik atau pengelola coffee shop. Hanya ada satu akun Owner di sistem. | Akses penuh ke semua master data (produk, kategori, stok, meja, user, promo), dashboard laporan, dan export CSV. Dapat melihat seluruh transaksi dan shift dari semua cashier. Owner tidak membuat transaksi penjualan dan tidak membuka shift. |
| **Cashier** | Staf kasir yang melayani pelanggan. Akunnya dibuat oleh Owner. | Membuka dan menutup shift miliknya sendiri, membuat transaksi, menerapkan promo yang sedang aktif, melakukan checkout, dan melihat riwayat transaksi pada shift aktifnya hari ini. Hanya bisa **membaca** daftar produk aktif, meja, dan promo aktif. Tidak bisa mengakses master data, laporan, maupun transaksi cashier lain. |

### Matriks Akses

| Modul | Owner | Cashier |
|---|---|---|
| Produk & Kategori | CRUD | Read (produk aktif saja) |
| Stok & Riwayat Stok | CRUD / Read | — |
| Meja | CRUD | Read + status meja |
| User Cashier | CRUD | — |
| Promo & Diskon | CRUD | Read (promo aktif saja) |
| Shift | Read (semua) | Buka/tutup (milik sendiri) |
| Transaksi | Read (semua) | Create, Read (shift sendiri hari ini) |
| Dashboard & Export CSV | Ya | — |

**Acceptance Criteria (Autentikasi & Otorisasi)**
- [ ] User login dengan username dan password, lalu menerima token sesi (mis. JWT) yang memiliki masa berlaku.
- [ ] Password disimpan dalam bentuk hash (bcrypt), tidak pernah dalam bentuk plain text.
- [ ] Setiap endpoint memvalidasi role. Akses ke endpoint di luar hak role menghasilkan HTTP 403.
- [ ] Cashier dengan status nonaktif tidak bisa login.

---

## 3. Fitur Owner

### 3.1 Manajemen Produk
Owner mengelola daftar menu yang dijual.

**Atribut produk:** nama, SKU/kode unik, kategori, harga jual, deskripsi (opsional), foto (opsional), status (aktif/nonaktif), lacak stok (ya/tidak), stok saat ini, batas stok minimum.

**Kemampuan:**
- Membuat, melihat (list dengan pencarian, filter kategori/status, dan pagination), mengubah, dan menghapus produk.
- Menghapus produk memakai **soft delete** (`deleted_at` diisi). Data produk tetap ada untuk keperluan riwayat transaksi dan laporan.
- Upload foto produk (JPG/PNG/WebP, maksimal 2 MB).
- Mengubah status aktif/nonaktif. Produk nonaktif tidak muncul di layar kasir.

**Acceptance Criteria**
- [ ] Owner dapat membuat produk dengan field wajib (nama, kategori, harga). Validasi gagal mengembalikan pesan error per field.
- [ ] SKU harus unik di antara produk yang belum dihapus.
- [ ] Harga harus berupa bilangan bulat ≥ 0 (dalam Rupiah).
- [ ] Upload foto menolak file dengan format selain JPG/PNG/WebP atau berukuran > 2 MB. Foto yang berhasil diunggah dapat diakses melalui URL.
- [ ] Produk yang di-soft delete tidak muncul di list Owner (kecuali dengan filter "terhapus") maupun di layar kasir, tetapi tetap tampil dengan benar di detail transaksi lama.
- [ ] Produk nonaktif tidak bisa ditambahkan ke transaksi baru.
- [ ] Perubahan harga tidak mengubah harga di transaksi yang sudah dibuat.

### 3.2 Manajemen Kategori Produk
**Atribut kategori:** nama, urutan tampil, status aktif.

**Acceptance Criteria**
- [ ] Owner dapat membuat, melihat, mengubah, dan menghapus kategori.
- [ ] Nama kategori harus unik.
- [ ] Kategori yang masih memiliki produk (yang belum dihapus) tidak bisa dihapus. Sistem menampilkan pesan error yang jelas.
- [ ] Urutan tampil menentukan urutan tab kategori di layar kasir.

### 3.3 Manajemen Stok & Riwayat Pergerakan Stok
Stok hanya dilacak untuk produk yang memiliki flag "lacak stok" (mis. kue, botol minuman). Minuman racikan bisa tidak dilacak.

**Jenis pergerakan stok:**

| Tipe | Arah | Pemicu |
|---|---|---|
| `IN` (stok masuk / restock) | + | Input manual Owner |
| `OUT_SALE` (penjualan) | − | Otomatis saat transaksi lunas |
| `ADJUSTMENT` (penyesuaian / opname) | ± | Input manual Owner, wajib disertai alasan |
| `WASTE` (rusak/kedaluwarsa) | − | Input manual Owner, wajib disertai alasan |
| `RETURN_VOID` (pengembalian) | + | Otomatis saat transaksi lunas dibatalkan/di-refund (jika fitur ini ada) |

**Acceptance Criteria**
- [ ] Owner dapat menambah stok masuk, penyesuaian, dan waste untuk sebuah produk, disertai jumlah dan catatan.
- [ ] Setiap pergerakan stok tercatat di tabel riwayat berisi: produk, tipe, jumlah, stok sebelum, stok sesudah, referensi (ID transaksi jika ada), user pelaku, dan waktu.
- [ ] Riwayat stok bersifat **append-only**. Data riwayat tidak bisa diedit atau dihapus.
- [ ] Owner dapat melihat riwayat stok per produk dengan filter rentang tanggal dan tipe pergerakan.
- [ ] Produk dengan stok ≤ batas minimum ditandai "stok menipis" di daftar produk Owner.
- [ ] Nilai stok saat ini selalu sama dengan total semua pergerakan pada riwayat.

### 3.4 Manajemen Meja
**Atribut meja:** nomor/nama meja (unik), kapasitas, status (`AVAILABLE`, `OCCUPIED`), aktif/nonaktif.

**Acceptance Criteria**
- [ ] Owner dapat membuat, melihat, mengubah, dan menghapus (soft delete) meja.
- [ ] Nomor meja harus unik.
- [ ] Meja yang sedang `OCCUPIED` (masih punya transaksi yang belum selesai) tidak bisa dihapus atau dinonaktifkan.
- [ ] Meja nonaktif tidak muncul di pilihan meja kasir.

### 3.5 Manajemen User Cashier
**Atribut user:** nama lengkap, username (unik), password, status aktif/nonaktif.

**Acceptance Criteria**
- [ ] Owner dapat membuat akun cashier baru dengan username unik dan password minimal 8 karakter.
- [ ] Owner dapat mengubah data cashier dan mereset password cashier.
- [ ] Owner dapat menonaktifkan cashier. Cashier yang dinonaktifkan langsung kehilangan akses (token tidak berlaku lagi pada request berikutnya).
- [ ] Cashier yang sedang memiliki shift terbuka tidak bisa dinonaktifkan sampai shift-nya ditutup.
- [ ] Akun cashier tidak di-hard delete agar riwayat transaksi dan shift tetap utuh.

### 3.6 Dashboard Laporan
Laporan hanya menghitung transaksi berstatus `PAID`.

**Isi dashboard:**
- **Revenue** harian, mingguan, dan bulanan: total penjualan kotor, total diskon, penjualan bersih, jumlah transaksi, dan rata-rata nilai transaksi. Disertai grafik tren.
- **Produk terlaris**: top N produk berdasarkan jumlah terjual dan berdasarkan revenue, dalam rentang tanggal tertentu.
- **Transaksi per cashier**: jumlah transaksi, total revenue, dan total diskon per cashier dalam rentang tanggal tertentu.
- **Ringkasan shift**: daftar shift beserta selisih kas.

**Acceptance Criteria**
- [ ] Owner dapat memilih periode (hari ini, 7 hari, 30 hari, bulan ini, atau rentang tanggal custom).
- [ ] Angka revenue di dashboard sama persis dengan total transaksi `PAID` pada periode yang dipilih.
- [ ] Transaksi `PENDING`, `FAILED`, `EXPIRED`, dan `CANCELLED` tidak dihitung dalam laporan.
- [ ] Perhitungan tanggal memakai zona waktu outlet (default `Asia/Jakarta`).
- [ ] Dashboard untuk rentang 30 hari tampil dalam waktu ≤ 3 detik pada data 30.000 transaksi.

### 3.7 Manajemen Promo & Diskon
**Atribut promo:** nama, kode promo (opsional), tipe (`PERCENTAGE` / `FIXED`), nilai, minimum belanja (opsional), maksimum potongan (untuk tipe persentase, opsional), tanggal mulai, tanggal berakhir, status aktif/nonaktif.

Promo berlaku untuk **total transaksi** (level order).

**Acceptance Criteria**
- [ ] Owner dapat membuat, melihat, mengubah, dan menonaktifkan promo.
- [ ] Nilai promo persentase harus berada di antara 1–100. Nilai promo nominal harus > 0.
- [ ] Tanggal berakhir tidak boleh sebelum tanggal mulai.
- [ ] Promo dianggap "aktif" hanya jika statusnya aktif **dan** waktu saat ini berada di dalam rentang tanggal promo.
- [ ] Mengubah atau menonaktifkan promo tidak mengubah nilai diskon pada transaksi yang sudah dibuat.
- [ ] Promo yang sudah pernah dipakai tidak bisa di-hard delete, hanya bisa dinonaktifkan.

### 3.8 Export Laporan ke CSV
**Laporan yang bisa di-export:**
- Daftar transaksi (header: no. transaksi, tanggal, cashier, meja, subtotal, diskon, total, metode bayar, status).
- Detail item transaksi.
- Rekap penjualan per produk.
- Rekap per cashier.
- Rekap shift.
- Riwayat pergerakan stok.

**Acceptance Criteria**
- [ ] Owner dapat meng-export setiap laporan di atas sesuai filter periode yang sedang dipilih.
- [ ] File CSV berencoding UTF-8 (dengan BOM agar terbaca benar di Excel), memakai pemisah koma, dan baris pertamanya berisi header.
- [ ] Nama file mengikuti format `<jenis-laporan>_<tanggal-awal>_<tanggal-akhir>.csv`.
- [ ] Isi CSV konsisten dengan angka yang tampil di dashboard pada periode yang sama.
- [ ] Export 30.000 baris berhasil tanpa timeout (menggunakan streaming response).

---

## 4. Fitur Cashier

### 4.1 Manajemen Shift
**Buka shift:** cashier memasukkan modal kas awal (uang tunai di laci).
**Tutup shift:** cashier memasukkan jumlah kas aktual yang dihitung secara fisik, lalu sistem menampilkan rekap.

**Isi rekap tutup shift:**
- Waktu buka dan tutup shift.
- Modal kas awal.
- Jumlah transaksi dan total penjualan per metode pembayaran.
- Total diskon.
- Kas yang diharapkan (modal awal + penjualan tunai).
- Kas aktual dan selisihnya (lebih/kurang).
- Catatan (wajib diisi jika ada selisih).

**Acceptance Criteria**
- [ ] Cashier tidak bisa membuat transaksi tanpa shift yang terbuka.
- [ ] Satu cashier hanya boleh memiliki satu shift terbuka pada satu waktu.
- [ ] Modal kas awal wajib diisi dengan angka ≥ 0.
- [ ] Shift tidak bisa ditutup jika masih ada transaksi `PENDING` di shift tersebut. Transaksi tersebut harus diselesaikan atau dibatalkan dulu.
- [ ] Rekap dihitung otomatis oleh sistem dan tersimpan permanen. Shift yang sudah ditutup tidak bisa dibuka atau diubah lagi.
- [ ] Owner dapat melihat semua shift beserta rekapnya.

### 4.2 Buat Transaksi Baru
**Alur:**
1. Pilih tipe pesanan: **Dine-in** (wajib memilih meja yang `AVAILABLE`) atau **Take-away** (tanpa meja).
2. Pilih produk dari daftar produk aktif, dikelompokkan per kategori, dengan fitur pencarian.
3. Atur quantity (tambah/kurang/hapus item) dan catatan per item (opsional, mis. "less sugar").
4. Sistem menghitung subtotal secara real-time.

**Acceptance Criteria**
- [ ] Hanya produk aktif dan belum dihapus yang muncul dan bisa ditambahkan.
- [ ] Quantity minimal 1. Untuk produk yang dilacak stoknya, quantity tidak boleh melebihi stok tersedia.
- [ ] Transaksi minimal berisi 1 item.
- [ ] Untuk dine-in, meja yang dipilih berubah status menjadi `OCCUPIED` saat transaksi dibuat.
- [ ] Harga satuan dan nama produk disimpan sebagai **snapshot** di item transaksi.
- [ ] Setiap transaksi memiliki nomor unik dengan format `TRX-YYYYMMDD-XXXX`.
- [ ] Transaksi tercatat dengan ID cashier dan ID shift yang aktif.
- [ ] Seluruh perhitungan harga dilakukan di **server**. Nilai total yang dikirim dari client diabaikan.

### 4.3 Apply Promo Aktif
**Acceptance Criteria**
- [ ] Kasir hanya bisa melihat dan memilih promo yang sedang aktif (lihat definisi di 3.7).
- [ ] Maksimal **satu promo** per transaksi.
- [ ] Promo ditolak dengan pesan yang jelas jika subtotal belum mencapai minimum belanja.
- [ ] Diskon persentase dihitung dari subtotal dan dibatasi oleh nilai maksimum potongan (jika ada). Diskon nominal tidak boleh melebihi subtotal, sehingga total tidak pernah negatif.
- [ ] Hasil pembulatan diskon memakai Rupiah bulat (dibulatkan ke bawah).
- [ ] Kasir dapat melepas promo sebelum checkout.
- [ ] Saat checkout, server memvalidasi ulang bahwa promo masih aktif. Jika promo sudah tidak aktif, checkout ditolak dan kasir diminta memperbarui transaksi.
- [ ] ID promo, tipe, nilai, dan besar potongan disimpan sebagai snapshot di transaksi.

### 4.4 Checkout dengan Midtrans Snap
**Alur:**
1. Kasir menekan "Checkout". Server memvalidasi transaksi (stok, promo, total) lalu membuat Snap transaction ke Midtrans dengan `order_id` = nomor transaksi.
2. Server mengembalikan `snap_token`. Client membuka popup/redirect Snap.
3. Pelanggan membayar (QRIS, e-wallet, virtual account, kartu, dll. sesuai konfigurasi Midtrans).
4. Midtrans mengirim **notifikasi webhook** ke server. Server memverifikasi lalu memperbarui status transaksi.
5. Saat status menjadi `PAID`: stok dikurangi, meja dibebaskan, dan struk dapat ditampilkan.

**Status transaksi:** `PENDING` → `PAID` / `FAILED` / `EXPIRED` / `CANCELLED`.

**Acceptance Criteria**
- [ ] Server membuat Snap token dengan nilai `gross_amount` yang sama dengan total transaksi, beserta item details (termasuk baris diskon sebagai item bernilai negatif agar total cocok).
- [ ] Status `PAID` **hanya** ditetapkan berdasarkan webhook Midtrans yang valid (signature key terverifikasi) atau hasil pengecekan status ke API Midtrans. Callback dari sisi client tidak dijadikan acuan.
- [ ] Webhook bersifat **idempotent**: notifikasi ganda untuk transaksi yang sama tidak mengurangi stok dua kali.
- [ ] Status Midtrans dipetakan sebagai berikut: `settlement`/`capture` (fraud_status `accept`) → `PAID`; `deny`/`failure` → `FAILED`; `expire` → `EXPIRED`; `cancel` → `CANCELLED`; `pending` → tetap `PENDING`.
- [ ] Jika pembayaran gagal atau kedaluwarsa, kasir dapat membuat ulang Snap token untuk transaksi yang sama dengan item yang sama (memakai `order_id` baru yang tetap terhubung ke transaksi), atau membatalkan transaksi.
- [ ] Setelah checkout, item dan promo transaksi terkunci. Request untuk mengubahnya ditolak server (BR-08).
- [ ] Saat transaksi `PAID`, pengurangan stok dan pencatatan riwayat stok terjadi dalam satu database transaction.
- [ ] Saat transaksi selesai (`PAID`/`CANCELLED`), meja dine-in kembali `AVAILABLE`.
- [ ] Server Key Midtrans disimpan di environment variable dan tidak pernah dikirim ke client.
- [ ] Mendukung mode Sandbox dan Production melalui konfigurasi.

### 4.5 Riwayat Transaksi Shift Hari Ini
**Acceptance Criteria**
- [ ] Kasir melihat daftar transaksi dari shift aktifnya: nomor transaksi, waktu, meja, total, dan status.
- [ ] Kasir dapat membuka detail transaksi (item, quantity, harga, diskon, total, metode bayar).
- [ ] Kasir dapat memfilter daftar berdasarkan status.
- [ ] Kasir dapat melanjutkan pembayaran untuk transaksi `PENDING` atau membatalkannya.
- [ ] Kasir tidak bisa melihat transaksi milik cashier lain atau transaksi dari shift sebelumnya.

---

## 5. Business Rules

### Umum
- **BR-01** Semua nilai uang disimpan dalam Rupiah sebagai bilangan bulat (`BIGINT`), bukan float.
- **BR-02** Semua waktu disimpan dalam UTC di database. Tampilan dan perhitungan laporan memakai zona waktu outlet (`Asia/Jakarta`).
- **BR-03** Data yang direferensikan transaksi (produk, kategori, meja, user, promo) tidak boleh di-hard delete, hanya di-soft delete atau dinonaktifkan.
- **BR-04** Seluruh operasi yang mengubah lebih dari satu tabel (checkout, perubahan status bayar, mutasi stok) wajib berjalan dalam satu database transaction.

### Transaksi & Harga
- **BR-05** Rumus total: `total = subtotal − diskon`, dengan `subtotal = Σ(harga_snapshot × qty)`. Total ≥ 0. Versi ini belum menghitung pajak dan service charge (lihat Out of Scope).
- **BR-06** Harga, nama produk, dan nilai promo disimpan sebagai snapshot saat transaksi dibuat. Perubahan master data tidak memengaruhi transaksi lama.
- **BR-07** Transaksi `PAID` bersifat final dan tidak bisa diedit maupun dihapus.
- **BR-08** Item transaksi (produk, quantity, catatan) hanya bisa diubah **sebelum checkout**. Begitu kasir menekan "Checkout" (Snap token dibuat), item terkunci dan tidak bisa ditambah, diubah, atau dihapus, termasuk saat status masih `PENDING`. Jika pelanggan ingin mengubah pesanan, transaksi harus dibatalkan (`CANCELLED`) dan kasir membuat transaksi baru. Server menolak setiap request perubahan item pada transaksi yang sudah checkout.
- **BR-09** Transaksi `PENDING` yang tidak dibayar dalam batas waktu (mengikuti expiry Midtrans, default 15 menit) berubah menjadi `EXPIRED`, dan meja dibebaskan.

### Stok
- **BR-10** Stok berkurang **hanya** setelah server menerima webhook Midtrans yang menyatakan pembayaran berhasil (`settlement`, atau `capture` dengan `fraud_status = accept`) dan signature-nya valid. Stok tidak berkurang saat item ditambahkan ke keranjang, saat checkout, maupun saat client menerima callback sukses dari Snap.
- **BR-11** Stok tidak boleh negatif. Jika saat webhook `PAID` stok ternyata tidak cukup (karena race condition), transaksi tetap `PAID` (uang sudah diterima), stok dicatat apa adanya, dan sistem membuat flag peringatan untuk Owner.
- **BR-12** Pengurangan stok memakai row-level locking (`SELECT ... FOR UPDATE`) untuk mencegah race condition.
- **BR-13** Setiap perubahan stok wajib memiliki entri di riwayat pergerakan stok.

### Shift
- **BR-14** Cashier **wajib membuka shift** sebelum bisa membuat transaksi baru. Server menolak pembuatan transaksi (HTTP 409/422) jika cashier tidak memiliki shift berstatus terbuka. Satu cashier hanya boleh memiliki satu shift terbuka, dan setiap transaksi selalu terikat pada shift tersebut.
- **BR-15** Kas yang diharapkan = modal awal + total transaksi `PAID` dengan metode tunai. Selisih = kas aktual − kas yang diharapkan.
- **BR-16** Shift yang sudah ditutup bersifat final.

### Promo
- **BR-17** Satu transaksi hanya bisa menggunakan **satu promo**. Promo tidak bisa digabung (non-stackable). Memasang promo kedua mengganti promo sebelumnya, bukan menambah. Promo hanya bisa dipasang atau dilepas sebelum checkout (lihat BR-08).
- **BR-18** Promo hanya berlaku jika aktif, berada di rentang tanggal yang berlaku, dan subtotal ≥ minimum belanja. Validasi dilakukan ulang di server saat checkout.
- **BR-19** Diskon tidak boleh membuat total menjadi negatif.

### Meja
- **BR-20** Satu meja hanya boleh memiliki satu transaksi aktif (`PENDING`) pada satu waktu.
- **BR-21** Meja kembali `AVAILABLE` saat transaksinya `PAID`, `CANCELLED`, `FAILED` (setelah dibatalkan), atau `EXPIRED`.

### Pembayaran & Keamanan
- **BR-22** Status pembayaran hanya ditentukan oleh webhook Midtrans yang terverifikasi signature-nya: `SHA512(order_id + status_code + gross_amount + server_key)`.
- **BR-23** Pemrosesan webhook bersifat idempotent berdasarkan `order_id` dan status terakhir.
- **BR-24** Owner dan Cashier hanya dapat mengakses data sesuai matriks akses di bagian 2.

> **Catatan metode tunai:** Midtrans Snap tidak menangani pembayaran tunai. Agar rekap kas shift (BR-15) relevan, sistem menyediakan metode **Tunai** sebagai jalur checkout alternatif: kasir memasukkan uang yang diterima, sistem menghitung kembalian, lalu transaksi langsung `PAID`. Karena tidak ada webhook pada jalur ini, BR-10 berlaku khusus untuk transaksi non-tunai. Untuk transaksi tunai, stok berkurang saat kasir mengonfirmasi penerimaan uang, dalam database transaction yang sama dengan perubahan status ke `PAID`. Jika versi ini hanya mendukung non-tunai, maka kas yang diharapkan sama dengan modal awal.

---

## 6. Out of Scope (Tidak Dibangun di Versi Ini)

- Multi-outlet / multi-cabang dan role tambahan (manager, barista, waiter).
- Pajak (PPN/PB1) dan service charge.
- Split bill, pembayaran gabungan (sebagian tunai, sebagian non-tunai), dan merge meja.
- Refund atau void transaksi yang sudah `PAID`.
- Manajemen resep dan bahan baku (BOM), misalnya pengurangan stok biji kopi atau susu per gelas.
- Varian dan modifier produk berbayar (size, extra shot, topping) sebagai entitas terpisah.
- Kitchen Display System (KDS) dan cetak order ke dapur/bar.
- Integrasi printer struk thermal dan cash drawer. Struk hanya ditampilkan di layar atau bisa dicetak lewat browser.
- Program loyalitas, membership, poin, dan database pelanggan (CRM).
- Promo level produk/kategori, promo bundling, buy X get Y, dan voucher sekali pakai.
- Self-order / QR order oleh pelanggan dan integrasi ojek online (GoFood, GrabFood, ShopeeFood).
- Mode offline.
- Aplikasi mobile native.
- Manajemen supplier dan purchase order.
- Akuntansi, payroll, dan absensi karyawan.
- Export ke format selain CSV (PDF, Excel).

---

## Lampiran A — Entitas Data Utama (Referensi)

`users`, `categories`, `products`, `stock_movements`, `tables`, `promos`, `shifts`, `transactions`, `transaction_items`, `payments` (log request/notifikasi Midtrans per `order_id`).
