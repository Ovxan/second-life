# Second Life

Web publik: https://ovxan.github.io/second-life/

Marketplace sirkular untuk mahasiswa dan alumni: jual beli, donasi, dan jasa reparasi.

## Berkas

- index.html: web lengkap dalam satu berkas, dengan CSS, JavaScript, dan foto ilustrasi tertanam. Katalog serta foto asli memakai Supabase dan memerlukan internet.
- second-life-source.zip: seluruh kode sumber, aset, skrip build, migrasi, dan tes. Ekstrak folder second-life lalu jalankan pnpm install, pnpm exec tsc --noEmit, pnpm test, dan pnpm build.
- database.sql: migrasi awal yang sudah diterapkan; jangan dijalankan ulang.
- accounts-admin.sql: migrasi akun terdaftar dan admin pemilik yang sudah diterapkan; jangan dijalankan ulang.

## Pengunjung dan akun

Katalog bisa dibaca tanpa login. Daftar, konfirmasi email, atur password, dan login diperlukan untuk menambah barang/donasi serta mengelola iklan. Akun hanya dapat mengubah iklan sendiri. Nama dan akun disimpan di Supabase Auth; password tidak ditanam pada HTML atau tabel publik.

Iklan versi lama tetap disimpan. Daftar dari browser yang masih menyimpan sesi tamu untuk menghubungkan email pada identitas tersebut. Verifikasi email dahulu, kemudian atur password. Login ke akun lain tidak otomatis memindahkan iklan lama.

## Admin pemilik web

Mode admin menggunakan login email/password. Pemilik yang diberi akses pada tabel site_admins dapat mengelola seluruh katalog. Akun biasa tidak otomatis menjadi admin dan tidak bisa menetapkan hak admin sendiri. Penambahan serta perubahan jasa reparasi hanya untuk admin. Sesi admin terpisah dari sesi akun pengunjung.

Akun admin pertama masih perlu ditetapkan oleh pemilik proyek melalui Supabase setelah akun dengan email terkonfirmasi dan password tersedia. Password diisi langsung melalui formulir akun, tidak dibagikan melalui repository.

## Aktivasi email

Email/password dan konfirmasi email diaktifkan. Pembuatan sesi anonim baru dinonaktifkan. Tautan verifikasi dan pemulihan diarahkan ke web publik yang benar. Layanan pengirim email khusus (SMTP) belum diaktifkan, sehingga verifikasi pendaftaran umum masih menunggu konfigurasi pengirim. Jangan menonaktifkan verifikasi email untuk mengatasi kendala tersebut. Pengaturan SMTP hanya dilakukan pada Supabase, bukan pada HTML.

## Harga

Harga barang + biaya admin Rp5.000 menjadi total pembeli; bagian penjual tetap sebesar harga barang. Contoh Rp150.000 + admin Rp5.000 = Rp155.000. Donasi dan informasi jasa tidak dikenai biaya admin platform. Penagihan, rekening penerima, bukti pembayaran, saldo pendapatan, dan pemotongan otomatis belum tersedia. Tidak ada promo potongan admin yang diaktifkan.

## Pemeriksaan

Pembaruan ini lolos TypeScript, build HTML satu berkas, 43 pemeriksaan kebijakan PostgreSQL/akun/admin, 20 pengujian harga, dan 6 pemeriksaan akses backend langsung tanpa membuat data uji baru. Pengiriman email pendaftaran dan login akun admin pertama belum dapat diuji sampai layanan email dan akun pemilik ditetapkan.

Iklan berlabel Contoh merupakan demonstrasi, bukan penawaran asli. Foto ilustrasi: Unsplash. Identitas kampus belum diverifikasi; akun terdaftar bukan jaminan bebas penipuan.
