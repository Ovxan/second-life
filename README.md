# Second Life

Web publik: https://ovxan.github.io/second-life/

Marketplace sirkular untuk mahasiswa dan alumni: jual beli, donasi, dan jasa reparasi. HTML mandiri memakai Supabase untuk katalog, akun, foto, dan tagihan bersama.

## Berkas

- index.html: HTML lengkap dengan CSS, JavaScript, dan foto ilustrasi tertanam.
- second-life-source.zip: kode sumber lengkap, aset, skrip build, migrasi, dan tes. Ekstrak folder second-life lalu jalankan pnpm install, pnpm exec tsc --noEmit, pnpm test, dan pnpm build.
- database.sql: migrasi katalog awal yang sudah diterapkan.
- accounts-admin.sql: migrasi akun dan peran admin yang sudah diterapkan.
- manual-billing.sql: migrasi tagihan dan bukti transfer privat yang sudah diterapkan.

Jangan menjalankan ulang migrasi pada proyek online yang sama. Untuk proyek baru, jalankan ketiganya satu kali sesuai urutan di atas.

## Akun dan admin

Katalog dapat dibaca tanpa login. Pemasangan barang dan tagihan memerlukan akun dengan email terkonfirmasi dan password. Akun biasa hanya mengubah iklannya sendiri. Pemilik yang terdaftar pada site_admins mengelola seluruh katalog; hanya admin dapat menambah atau mengubah jasa reparasi. Akun pemilik pertama pada proyek ini sudah diberi peran admin. Password diisi sendiri oleh pemilik melalui formulir akun, tidak disimpan pada kode.

Sesi tamu versi lama tetap disimpan. Daftar dari browser yang masih menyimpan sesi tersebut untuk menghubungkan email dan mempertahankan kepemilikan iklan. Login ke akun baru tidak otomatis memindahkan iklan lama.

## Harga dan penagihan manual

Harga barang + biaya admin Rp5.000 menjadi total pembeli. Contoh: Rp100.000 untuk penjual + Rp5.000 untuk pengelola = total Rp105.000. Penjual menerima harga barang penuh. Donasi dan informasi jasa reparasi tanpa biaya admin platform. Tidak ada promo potongan biaya admin.

1. Admin membuka https://ovxan.github.io/second-life/#adminbilling, mengisi rekening bank/e-wallet milik pengelola, dan mengaktifkan penagihan. Tanpa tujuan aktif, database menolak tagihan baru.
2. Pembeli menyelesaikan jual beli dan membayar harga barang langsung ke penjual.
3. Pembeli membuat tagihan biaya admin dari detail barang atau dari tautan barang melalui halaman Tagihan. Tautan tetap bisa dipakai jika barang sudah ditandai Terjual. Satu iklan mempunyai satu tagihan aktif agar biaya tidak ditagih ganda.
4. Pembeli mentransfer Rp5.000 ke tujuan pada tagihan dan mengunggah bukti maksimal 2 MB. Tujuan transfer serta harga pada tagihan tersimpan saat dibuat; perubahan pengaturan tidak mengubah tagihan lama.
5. Admin mencocokkan bukti dengan mutasi rekening/e-wallet lalu mengonfirmasi Lunas atau meminta perbaikan dengan alasan. Pembeli dapat memperbaiki bukti yang ditolak.

Status: Belum dibayar, Menunggu verifikasi, Perlu perbaikan, Lunas, Dibatalkan. Rekap pendapatan hanya menghitung biaya admin terkonfirmasi, bukan harga barang. Rekap mencakup semua tagihan; daftar UI menampilkan 100 tagihan terbaru. Penandaan Terjual tidak otomatis membuktikan atau menagih biaya admin.

Bukti disimpan pada bucket privat second-life-receipts, hanya dapat dibaca pembeli terkait dan admin dengan tautan gambar 60 detik. Riwayat verifikasi dan bukti sebelumnya disimpan. Menghapus iklan tidak menghapus arsip tagihan. Tagihan yang sedang diperiksa atau sudah lunas tidak dapat dibatalkan. Pembatalan tagihan belum dibayar tidak mengembalikan atau memindahkan uang; pengelola menangani refund transfer di luar web.

Tidak ada koneksi bank, payment gateway, debit/potongan otomatis, atau penyaluran harga barang melalui platform. Penagihan manual bergantung pada pembeli membuat tagihan dan pengelola memeriksa transfer.

## Pengiriman email

Email/password dan konfirmasi email diaktifkan. Sesi anonim baru dinonaktifkan. Layanan pengirim email khusus (SMTP) belum diaktifkan, sehingga pendaftaran pengunjung umum masih menunggu konfigurasi pengirim. Atur kredensial SMTP hanya melalui Supabase, bukan pada HTML/repository. Jangan mematikan verifikasi email untuk mengatasi kendala pengiriman.

## Pemeriksaan

Pembaruan ini diperiksa dengan TypeScript, build HTML satu berkas, 43 pemeriksaan kebijakan katalog/akun/admin, 20 pengujian harga, dan 50 pemeriksaan status, akuntansi, privasi, serta izin tagihan di PostgreSQL/PGlite. Pemeriksaan backend online menggunakan akses publik dan permintaan yang ditolak tanpa membuat akun atau tagihan uji. Belum ada transfer uang atau pengujian pembayaran nyata; tujuan pembayaran masih perlu diisi pemilik.

Iklan berlabel Contoh adalah demonstrasi, bukan penawaran asli. Foto ilustrasi: Unsplash. Identitas kampus belum diverifikasi; akun terdaftar bukan jaminan bebas penipuan.
