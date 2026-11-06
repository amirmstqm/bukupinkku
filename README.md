# 🌸 BukuPinkKu - Peneman Digital Kehamilan & Anak (0-3 Tahun)

Aplikasi web interaktif untuk merekodkan perkembangan kehamilan daripada "Buku Pink" Klinik Kesihatan (KKM) sehingga anak berumur 3 tahun, lengkap dengan ciri perkongsian data masa nyata bersama pasangan (*Partner Sync*).

---

## 🚀 Cara Menjalankan Prototaip Ini

### Cara 1: Buka Terus Dalam Pelayar Web (Paling Pantas)
Klik dua kali (double-click) pada fail:
`c:\Users\taufi\Downloads\bukupink-app\index.html`

### Cara 2: Menggunakan Pelayan Tempatan (Local Server)
Buka PowerShell / Terminal dan jalankan:
```bash
cd c:\Users\taufi\Downloads\bukupink-app
python server.py
```
Aplikasi akan dibuka secara automatik di pelayar anda di: `http://localhost:3000`

---

## ✨ Ciri-Ciri Utama Yang Ada Dalam Prototaip

1. **Simulasi Perkongsian Pasangan (Partner Switcher):**
   * Di bar atas, anda boleh klik antara **Sarah (Ibu)** dan **Amir (Suami)**.
   * Apabila beralih ke Amir, paparan bertukar dengan tips khusus untuk suami dan butang peringatan ubat.
2. **Dashboard Kehamilan (Buku Pink):**
   * Kiraan baki hari ke Tarikh Jangka Bersalin (EDD).
   * Perbandingan saiz bayi mengikut minggu kehamilan.
3. **Peringatan & Log Ubat:**
   * Tanda ubat telah diambil (cth: Iberet Folic Acid, Kalsium).
   * Butang *"Ingatkan Isteri"* untuk suami menghantar notifikasi peringatan.
4. **Log Bacaan Kesihatan Vital KKM:**
   * Memasukkan bacaan HB (Hemoglobin) dengan pengkategorian automatik mengikut piawaian KKM (Hijau: $\ge$ 11.0, Kuning: 9.0 - 10.9, Merah: < 9.0).
   * Tekanan darah (BP) dan berat badan.
5. **Pengurusan Janji Temu KK / Swasta:**
   * Senarai janji temu akan datang dengan senarai semak barang yang perlu dibawa (Buku Pink fizikal, sampel urin, kad pengenalan).
   * Borang tambah janji temu baru.
6. **Pantang & Alahan Ibu:**
   * Senarai makanan alahan/pantang untuk rujukan suami bila keluar tapau makanan.

---

## 🏗️ Pelan Seterusnya (Fasa Produksi)
* **Frontend:** Naik taraf ke Next.js + Tailwind PWA (boleh pasang di skrin telefon Android & iOS).
* **Backend & Database:** Sambung ke Supabase (PostgreSQL) menggunakan schema SQL yang telah disemak.
* **Notifikasi:** Integrasi Web Push / WhatsApp API untuk mengingatkan suami dan isteri secara automatik.
