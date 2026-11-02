# Second Life

Marketplace sirkular untuk mahasiswa dan alumni: jual beli, donasi, dan jasa reparasi.

**Buka web:** https://ovxan.github.io/second-life/

- `index.html`: web siap pakai dalam satu berkas. CSS, JavaScript, dan tujuh foto ilustrasi sudah tertanam. Katalog dan foto pengguna tersimpan di Supabase sehingga memerlukan internet.
- `second-life-source.zip`: seluruh kode sumber yang dapat diedit, aset asli, konfigurasi publik, lockfile, skrip build, dan tes. Ekstrak folder `second-life`, jalankan `pnpm install`, `pnpm exec tsc --noEmit`, `pnpm test`, dan `pnpm build`. Hasilnya adalah `index.html`. Petunjuk lengkap ada pada README di dalam arsip.
- `database.sql`: salinan migrasi yang **sudah diterapkan** pada proyek Supabase. Jangan dijalankan ulang pada proyek yang sama.

Pengunjung bisa membaca tanpa login. Sesi tamu dibuat saat pertama memasang iklan atau menyimpan favorit asli. Akses edit tersimpan pada browser dan perangkat yang sama; menghapus data browser atau memakai mode privat dapat menghilangkan akses pemilik. Belum ada pemulihan atau pemindahan akses antarperangkat. Katalog aktif dan foto bersifat publik, sementara edit/hapus dan favorit dibatasi melalui Row Level Security.

Nama dan WhatsApp ditayangkan setelah persetujuan pada formulir. Transaksi berlangsung langsung melalui WhatsApp. Pembayaran otomatis dan biaya layanan belum diaktifkan. Iklan berlabel “Contoh” adalah demonstrasi, bukan penawaran asli. Pengguna versi lama dapat memilih memindahkan iklan lewat Barang saya dengan persetujuan publikasi kontak.

Hanya URL proyek dan publishable key publik yang disertakan. Tidak ada secret key, password database, atau token sesi di berkas.

Validasi: TypeScript, build HTML satu berkas, 24 pemeriksaan kebijakan PostgreSQL/integritas, dan 15 pengujian langsung dengan dua sesi pengunjung. Foto ilustrasi: Unsplash. Identitas kampus belum diverifikasi dan moderasi admin belum tersedia.
