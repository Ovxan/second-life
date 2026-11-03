# Second Life

Marketplace sirkular untuk mahasiswa dan alumni: jual beli, donasi, dan jasa reparasi.

**Buka web:** https://ovxan.github.io/second-life/

- `index.html`: web siap pakai dalam satu berkas. CSS, JavaScript, dan tujuh foto ilustrasi sudah tertanam. Katalog dan foto pengguna tersimpan di Supabase sehingga memerlukan internet.
- `second-life-source.zip`: seluruh kode sumber yang dapat diedit, aset asli, konfigurasi publik, lockfile, skrip build, dan tes. Ekstrak folder `second-life`, jalankan `pnpm install`, `pnpm exec tsc --noEmit`, `pnpm test`, dan `pnpm build`. Hasilnya adalah `index.html`. Petunjuk lengkap ada pada README di dalam arsip.
- `database.sql`: salinan migrasi yang **sudah diterapkan** pada proyek Supabase. Jangan dijalankan ulang pada proyek yang sama.

**Rincian biaya admin:** harga barang ditambah Rp5.000 untuk pengelola, sedangkan bagian penjual tetap sebesar harga barang. Contoh Rp150.000 + Rp5.000 = total Rp155.000. Donasi dan informasi jasa tidak dikenai biaya admin platform. Katalog, detail, formulir, filter/urutan total, pesan WhatsApp, dan salin info memakai perhitungan yang sama. Ini baru rincian penawaran: penagihan, rekening penerima, bukti pembayaran, dan pemotongan otomatis belum tersedia. Status Terjual bukan bukti pembayaran biaya admin. Tidak ada promo potongan admin yang diaktifkan.

Pengunjung bisa membaca tanpa login. Sesi tamu dibuat saat pertama memasang iklan atau menyimpan favorit asli. Akses edit tersimpan pada browser dan perangkat yang sama; menghapus data browser atau memakai mode privat dapat menghilangkan akses pemilik. Belum ada pemulihan atau pemindahan akses antarperangkat. Katalog aktif dan foto bersifat publik, sementara edit/hapus dan favorit dibatasi melalui Row Level Security.

Nama dan WhatsApp ditayangkan setelah persetujuan pada formulir. Transaksi berlangsung langsung melalui WhatsApp. Penagihan biaya admin dan pembayaran otomatis belum diaktifkan. Iklan berlabel “Contoh” adalah demonstrasi, bukan penawaran asli. Pengguna versi lama dapat memilih memindahkan iklan lewat Barang saya dengan persetujuan publikasi kontak.

Hanya URL proyek dan publishable key publik yang disertakan. Tidak ada secret key, password database, atau token sesi di berkas.

Validasi: TypeScript, build HTML satu berkas, 24 pemeriksaan kebijakan PostgreSQL/integritas, dan 15 pengujian langsung dengan dua sesi pengunjung. Foto ilustrasi: Unsplash. Identitas kampus belum diverifikasi dan moderasi admin belum tersedia.

Validasi pembaruan biaya admin: 20 pengujian perhitungan dan tampilan harga, pemeriksaan TypeScript, serta build HTML satu berkas.
