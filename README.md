# LTP ระบบภาษี

ระบบจัดการภาษีซื้อ-ขาย, สต๊อค FIFO, ออกใบกำกับภาษี  
สำหรับ **แอล ที พี บิวดิ้ง ซัพพลายส์**

🌐 **เปิดใช้งาน:** https://YOUR_USERNAME.github.io/ltp-tax

---

## ฟีเจอร์หลัก

- 📁 ไฟล์หลักใบกำกับภาษีซื้อ (multi-select, bulk assign)
- 🧾 ภาษีซื้อ / ภาษีขาย รายเดือน
- 📦 สต๊อค FIFO อัตโนมัติ
- 📄 ออกใบกำกับภาษี 3 สำเนา (ถูกต้องตามกฎหมาย)
- 🤖 AI อ่าน PDF ใบกำกับอัตโนมัติ
- 👥 ฐานข้อมูลลูกค้า
- ☁️ Sync ผ่าน Supabase (realtime)
- 🔐 Login ด้วย Email + ระบบสิทธิ์ Admin/User

---

## การติดตั้ง Supabase (ครั้งแรก)

### 1. สมัคร Supabase
- ไป https://supabase.com → Sign up ฟรี
- New project → ชื่อ "LTP Tax System" → Region: Singapore

### 2. สร้าง Tables
- ไปที่ SQL Editor → วางโค้ดจาก `supabase_setup.sql` → Run

### 3. สร้าง Admin User
- Authentication → Users → Invite user → ใส่ email
- หลัง invite รัน SQL:
```sql
UPDATE profiles SET role='admin', name='Admin LTP' 
WHERE email='your@email.com';
```

### 4. ตั้งค่าในระบบ
- เปิด https://YOUR_USERNAME.github.io/ltp-tax
- กด "ตั้งค่า Supabase" ในหน้า Login
- ใส่ Project URL และ Anon Key (จาก Settings → API)

---

## การตั้งค่า Google Drive PDF (ไม่บังคับ)

1. ไป https://script.google.com → New project
2. วางโค้ดจาก `google_drive_script.js`
3. Deploy → Web app → Execute as: Me, Anyone with access
4. Copy URL → ใส่ในหน้าตั้งค่าระบบ

---

## อัปเดตระบบ

```bash
# แก้ไข index.html แล้ว push
git add .
git commit -m "update"
git push
```
ทุกคนจะได้เวอร์ชันใหม่ทันทีโดยไม่ต้องส่งไฟล์ใหม่
