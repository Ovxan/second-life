# Second Life

Web publik: https://ovxan.github.io/second-life/

Marketplace sirkular mahasiswa dan alumni untuk jual beli, donasi, dan jasa reparasi. HTML satu berkas memakai Supabase untuk akun, katalog, foto, dan tagihan bersama.

## Akun dan pengelolaan

Pemilik dan anggota masuk melalui Masuk/Daftar. Akun terverifikasi dapat memasang barang dan mengelola iklannya sendiri. Menu Dashboard pemilik, pengelolaan jasa reparasi, dan Penagihan & pendapatan hanya muncul setelah peran pemilik diverifikasi database. Hak admin tetap diperiksa di database untuk setiap tindakan; menyembunyikan menu bukan satu-satunya perlindungan.

Akun pemilik pertama sudah diberi peran admin. Password diisi sendiri melalui alur email terverifikasi, tidak ditanam di HTML. Iklan lama tetap disimpan; konversi akun tamu perlu dilakukan dari browser yang menyimpan sesi lama agar kepemilikan tetap terhubung.

## Harga dan tagihan penjual

Pembeli membayar harga barang yang tercantum kepada penjual. Biaya admin tetap Rp5.000 dan menjadi kewajiban penjual setelah barang berstatus Terjual. Contoh: harga barang Rp100.000, pembayaran pembeli Rp100.000, biaya admin penjual Rp5.000, sisa setelah biaya admin Rp95.000. Donasi dan informasi jasa reparasi tanpa biaya admin platform. Tidak ada promo atau biaya tambahan pembeli yang diaktifkan.

Setelah bertransaksi langsung dan menerima pembayaran barang, penjual mengubah status iklannya menjadi Terjual. Notifikasi pembayaran biaya admin muncul dengan tombol untuk membuka tagihan; penjual dapat memilih Nanti dan membukanya kembali melalui Tagihan saya. Database menyimpan status Terjual dan menerbitkan satu tagihan Rp5.000 ke akun penjual dalam transaksi yang sama. Tidak ada kode atau akun pembeli yang harus dimasukkan. Jika perubahan status gagal, tagihan juga dibatalkan oleh transaksi database. Pengulangan konfirmasi memakai tagihan yang sama. Tersedia dan Dalam proses tidak memicu tagihan. Moderator yang menyelesaikan iklan orang lain tetap menagih pemilik asli iklan.

Tagihan muncul pada Tagihan saya milik penjual. Halaman memantau perubahan privat dengan realtime dan pembaruan saat kembali ke tab. Jika tujuan transfer belum aktif, tagihan menunggu tujuan pembayaran; penjualan tetap dapat dicatat. Pengelola mengisi bank/e-wallet melalui Penagihan & pendapatan. Saat diaktifkan, tujuan diisikan satu kali pada tagihan yang masih kosong; tujuan yang sudah tersimpan pada tagihan lama tidak diganti.

Penjual mentransfer Rp5.000 dan mengunggah bukti JPG/PNG/WebP maksimal 2 MB. Admin mencocokkan nominal, waktu, dan pengirim dengan mutasi penerima sebelum mengonfirmasi Lunas. Tagihan belum dibayar atau bukti yang perlu diperbaiki dapat dibatalkan oleh admin jika penjualan memang dibatalkan. Penjual tidak dapat menghapus kewajiban penjualan yang aktif atau mengonfirmasi tagihannya sendiri. Penghapusan iklan tidak menghapus arsip tagihan. Status Terjual dan status Lunas biaya admin adalah dua hal terpisah.

Biaya tetap Rp5.000 juga berarti sisa penjual dapat negatif jika harga barang kurang dari Rp5.000. Formulir menampilkan peringatan dan rincian sebelum iklan ditayangkan; tidak ada potongan biaya admin yang diasumsikan otomatis.

Bukti tersimpan pada bucket privat second-life-receipts. Penanggung tagihan dan admin dapat membukanya dengan tautan gambar 60 detik. Riwayat bukti serta verifikasi dipertahankan. Tagihan sebelum perubahan kebijakan tetap mencatat penanggung dan pembayaran aslinya; tagihan lama yang belum diselesaikan perlu diperiksa admin sebelum penerbitan baru untuk barang yang sama. Pembayaran lama yang telah lunas tidak ditagih dua kali.

Rekap pendapatan hanya mencakup biaya admin yang terverifikasi masuk. Harga barang serta tagihan yang belum dibayar tidak dihitung sebagai penerimaan. Daftar UI menampilkan 100 tagihan terbaru; rekap mencakup semua tagihan. Web tidak terhubung ke saldo bank/e-wallet, tidak memotong saldo otomatis, tidak menahan atau menyalurkan harga barang, dan tidak menjalankan refund uang. Pengelola menangani pengecekan transfer dan refund di luar web.

## Pemeriksaan dokumen kampus

Pemasangan iklan baru oleh anggota memerlukan konfirmasi email, password, dan satu pengajuan KTM atau bukti alumni yang disetujui admin. KTP, NIM, NIK, pencocokan biometrik, serta OTP WhatsApp tidak diterapkan. Pemilik web tetap memakai peran admin yang sudah disetujui untuk mengelola platform; peran ini tidak otomatis memberi label dokumen ditinjau pada iklan pemilik.

Anggota membuka Akun saya, mengisi nama sesuai dokumen serta kampus, memilih KTM atau bukti alumni, membaca penggunaan data, lalu mengunggah foto JPG/PNG/WebP maksimal 2 MB. Foto diolah ulang menjadi JPEG dan metadata sumber tidak disalin. Minta pengguna menutup data yang tidak diperlukan seperti NIM, NIK, alamat, nomor rekening, barcode, atau QR. Dokumen hanya untuk pemeriksaan manual nama dan kampus, bukan validasi resmi database kampus atau jaminan transaksi.

Pemilik masuk ke Akun pemilik → Pemeriksaan dokumen kampus, membuka foto privat, lalu menyetujui atau meminta perbaikan dengan alasan. Nama pada iklan baru ditetapkan database mengikuti dokumen yang disetujui. Label publik hanya menampilkan “Dokumen kampus ditinjau admin” dan nama kampus, untuk iklan yang nama pemiliknya sesuai. Dokumen, email akun, ID pengajuan, dan direktori identitas tidak disediakan melalui proyeksi publik.

Bucket second-life-campus-documents bersifat privat dengan RLS. Hanya akun pengaju serta admin yang dapat membuka foto melalui tautan 60 detik. Pengunggahan hanya untuk draft yang diterbitkan server; berkas pengajuan terkirim tidak dapat diganti. Status persetujuan hanya dapat diubah melalui fungsi yang memeriksa peran admin, keadaan terbaru, dan keberadaan berkas. Satu pengajuan aktif per akun; maksimal lima pengajuan baru per hari. Admin tidak dapat menyetujui dokumennya sendiri.

Setelah keputusan atau penarikan, aplikasi mencoba menghapus foto melalui Storage API dan mencatat penghapusan hanya setelah berkas benar-benar tidak ada. Jika gagal, akun pengaju dan admin melihat bahwa foto menunggu penghapusan serta dapat mencoba kembali. Foto draft yang ditinggalkan disimpan sampai pengajuan ditarik. Tidak ada pekerjaan terjadwal untuk menghapus dokumen. Nama, kampus, persetujuan, dan riwayat keputusan dipertahankan selama akun digunakan, sesuai penjelasan sebelum pengunggahan; foto tidak disertakan dalam repository atau arsip kode.

Pengaju dapat menarik pengajuan atau mencabut persetujuannya sendiri. Admin dapat mencabut persetujuan dengan alasan. Pencabutan segera memblokir iklan baru di database dan menghilangkan label pada pembacaan katalog berikutnya. Katalog memperbarui data saat kembali ke tab dan berkala. Iklan lama tidak dihapus atau otomatis disetujui; pemilik tetap dapat mengelola barang dan membayar tagihannya selama menunggu. Tidak ada akun, dokumen, atau pengajuan nyata yang dibuat untuk pengujian.

## Berkas dan instalasi

- index.html: HTML lengkap dengan skrip, CSS, dan foto ilustrasi tertanam.
- second-life-source.zip: sumber lengkap, aset, migrasi, skrip build, dan tes. Ekstrak second-life, lalu jalankan pnpm install, pnpm exec tsc --noEmit, pnpm test, dan pnpm build.
- database.sql: migrasi katalog awal.
- accounts-admin.sql: migrasi akun serta peran pemilik.
- manual-billing.sql: struktur awal tagihan serta bukti privat.
- sold-billing.sql: migrasi lanjutan untuk tagihan penjual otomatis setelah Terjual.
- campus-verification.sql: migrasi pemeriksaan dokumen kampus dan pembatasan iklan baru.

Untuk proyek baru, jalankan kelima migrasi satu kali sesuai urutan di atas. Jangan menjalankan ulang migrasi yang sudah diterapkan pada proyek yang sama. URL proyek dan publishable key boleh berada pada kode; secret key, password database, dan kredensial SMTP tidak boleh dimasukkan ke repository.

## Email dan pemeriksaan

Email/password serta konfirmasi email diaktifkan. Pendaftaran pengunjung umum masih memerlukan pengaturan layanan email khusus (SMTP). Kredensialnya hanya diatur di Supabase; konfirmasi email tetap dipertahankan.

Pengujian lokal mencakup harga, RLS dan peran pemilik, tagihan penjual, migrasi riwayat lama, kegagalan transaksi, idempotensi, tujuan transfer, bukti privat, pemeriksaan dokumen kampus beserta penarikan/pencabutan dan privasinya, serta visibilitas menu. Seluruh pengujian kebijakan memakai kelima migrasi; akun yang sudah disetujui pada tes adalah data simulasi terisolasi, bukan persetujuan otomatis pada proyek online. Pemeriksaan backend online menggunakan pembacaan publik dan permintaan yang wajib ditolak tanpa membuat akun, penjualan, atau tagihan uji. Belum ada transfer uang nyata yang diuji.

Iklan berlabel Contoh adalah demonstrasi, bukan penawaran asli. Foto ilustrasi: Unsplash. Identitas kampus belum diverifikasi; akun terdaftar bukan jaminan bebas penipuan.
