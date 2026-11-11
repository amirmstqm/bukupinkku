import os
import re

html_path = r'c:\Users\taufi\Downloads\bukupink-app\index.html'
landing_comp_path = r'c:\Users\taufi\Downloads\bukupink-app\landing_page_component.html'
sw_path = r'c:\Users\taufi\Downloads\bukupink-app\sw.js'

with open(landing_comp_path, 'r', encoding='utf-8') as f:
    landing_html = f.read()

with open(html_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Insert landing page before screen-onboarding
target_onboard_header = '  <!-- ============================================================== -->\n  <!-- [SKRIN 1] ONBOARDING & DAFTAR KELUARGA (PENGGUNA BARU)        -->\n  <!-- ============================================================== -->'
assert target_onboard_header in content, "target_onboard_header not found"

replacement_onboard_header = landing_html + '\n\n' + target_onboard_header
content = content.replace(target_onboard_header, replacement_onboard_header, 1)

# 2. Update screen-onboarding div to start with hidden, and add back-to-landing button in onboarding header
old_onboard_div = '<div id="screen-onboarding" class="min-h-screen flex items-center justify-center p-4">'
new_onboard_div = '<div id="screen-onboarding" class="min-h-screen flex items-center justify-center p-4 hidden">'
assert old_onboard_div in content, "old_onboard_div not found"
content = content.replace(old_onboard_div, new_onboard_div, 1)

old_onboard_lang = '''      <!-- Pilihan Bahasa (BM / EN) di Atas Onboarding -->
      <div class="flex justify-end">
        <div class="inline-flex bg-slate-100 p-1 rounded-xl border border-slate-200 text-[11px] font-bold">
          <button type="button" onclick="switchLanguage('ms')" id="btn-lang-onboard-ms" class="px-2.5 py-1 rounded-lg bg-white text-pastel-600 shadow-sm transition">🇲🇾 BM</button>
          <button type="button" onclick="switchLanguage('en')" id="btn-lang-onboard-en" class="px-2.5 py-1 rounded-lg text-slate-500 hover:text-slate-800 transition">🇬🇧 EN</button>
        </div>
      </div>'''

new_onboard_lang = '''      <!-- Header Onboarding: Butang Kembali ke Laman Utama & Pilihan Bahasa -->
      <div class="flex justify-between items-center">
        <button type="button" onclick="showLandingScreen()" class="inline-flex items-center space-x-1.5 text-xs text-slate-500 hover:text-pastel-600 font-bold transition">
          <i data-lucide="arrow-left" class="w-3.5 h-3.5"></i>
          <span data-i18n="btn_back_home">Laman Utama</span>
        </button>
        <div class="inline-flex bg-slate-100 p-1 rounded-xl border border-slate-200 text-[11px] font-bold">
          <button type="button" onclick="switchLanguage('ms')" id="btn-lang-onboard-ms" class="px-2.5 py-1 rounded-lg bg-white text-pastel-600 shadow-sm transition">🇲🇾 BM</button>
          <button type="button" onclick="switchLanguage('en')" id="btn-lang-onboard-en" class="px-2.5 py-1 rounded-lg text-slate-500 hover:text-slate-800 transition">🇬🇧 EN</button>
        </div>
      </div>'''
assert old_onboard_lang in content, "old_onboard_lang not found"
content = content.replace(old_onboard_lang, new_onboard_lang, 1)

# 3. Add link to Landing Page in sidebar
old_sidebar_btn = '          <!-- 💖 DUITNOW INFAQ / SUPPORT BUTTON -->'
new_sidebar_btn = '''          <!-- 🌐 LAMAN UTAMA & PENERANGAN BUKUPINKKU -->
          <button onclick="showLandingScreen(); toggleSidebar(false);" class="w-full flex items-center justify-between px-3 py-2.5 rounded-xl bg-slate-50 hover:bg-slate-100 text-slate-700 text-xs font-bold border border-slate-200 transition">
            <span class="flex items-center space-x-2">
              <span class="text-base">🌐</span>
              <span data-i18n="btn_view_landing">Laman Utama & Info</span>
            </span>
            <span class="text-[10px] text-slate-400">&rarr;</span>
          </button>

          <!-- 💖 DUITNOW INFAQ / SUPPORT BUTTON -->'''
assert old_sidebar_btn in content, "old_sidebar_btn not found"
content = content.replace(old_sidebar_btn, new_sidebar_btn, 1)

# 4. Add I18N keys for MS
old_i18n_ms = '        onboard_subtitle: "Peneman Digital Kehamilan Buku Pink sehingga Anak Umur 3 Tahun bersama Pasangan",'
new_i18n_ms = '''        btn_back_home: "Laman Utama",
        btn_view_landing: "Laman Utama & Info",
        landing_nav_enter_code: "Masuk Kod",
        landing_nav_get_started: "Mula Percuma",
        landing_hero_badge: "Peneman Digital Kehamilan & Anak #1 Malaysia",
        landing_hero_h1: "Buku Pink Digital Yang Menghubungkan <span class=\\"text-transparent bg-clip-text bg-gradient-to-r from-pastel-600 to-rose-500\\">Suami & Isteri.</span>",
        landing_hero_desc: "Daripada ikhtiar zuriat (TTC), rekod temujanji & paras HB kehamilan, sehinggalah jadual vaksin anak umur 3 tahun. Telefon suami sentiasa diselaraskan secara masa nyata.",
        landing_hero_cta_start: "Mula Guna Percuma Sekarang",
        landing_hero_cta_code: "Saya Pasangan (Masuk Kod)",
        landing_kkm_notice: "BukuPinkKu adalah aplikasi peneman digital untuk membantu ibu dan pasangan memahami maklumat kehamilan & kesihatan anak. <strong>Ia BUKAN pengganti buku pink fizikal KKM yang sah</strong> — anda tetap wajib membawa Buku Pink fizikal setiap kali hadir ke Klinik Kesihatan atau hospital.",
        onboard_subtitle: "Peneman Digital Kehamilan Buku Pink sehingga Anak Umur 3 Tahun bersama Pasangan",'''
assert old_i18n_ms in content, "old_i18n_ms not found"
content = content.replace(old_i18n_ms, new_i18n_ms, 1)

# 5. Add I18N keys for EN
old_i18n_en = '        onboard_subtitle: "Digital Pregnancy (Pink Book) & Child Growth Companion (0–3 Years) for Couples",'
new_i18n_en = '''        btn_back_home: "Home",
        btn_view_landing: "Home & Info",
        landing_nav_enter_code: "Enter Code",
        landing_nav_get_started: "Get Started",
        landing_hero_badge: "Malaysia\'s #1 Digital Pregnancy Companion",
        landing_hero_h1: "The Digital Pink Book Companion Connecting <span class=\\"text-transparent bg-clip-text bg-gradient-to-r from-pastel-600 to-rose-500\\">Husband & Wife.</span>",
        landing_hero_desc: "From fertility planning (TTC), pregnancy clinic visits & HB levels, to KKM child vaccine schedules. Kept in sync with your partner\'s phone in real-time.",
        landing_hero_cta_start: "Start Free Now",
        landing_hero_cta_code: "I Am a Partner (Enter Code)",
        landing_kkm_notice: "BukuPinkKu is a digital companion web app designed to help parents easily understand and monitor health records. <strong>It is NOT a replacement for the official physical KKM Pink Book</strong> — you are still required to bring your physical Pink Book to every clinic visit.",
        onboard_subtitle: "Digital Pregnancy (Pink Book) & Child Growth Companion (0–3 Years) for Couples",'''
assert old_i18n_en in content, "old_i18n_en not found"
content = content.replace(old_i18n_en, new_i18n_en, 1)

# 6. Update switchLanguage to style landing page language buttons
old_switch_lang = '''      const obMs = document.getElementById('btn-lang-onboard-ms');
      const obEn = document.getElementById('btn-lang-onboard-en');
      const dbMs = document.getElementById('btn-lang-dash-ms');
      const dbEn = document.getElementById('btn-lang-dash-en');'''

new_switch_lang = '''      const obMs = document.getElementById('btn-lang-onboard-ms');
      const obEn = document.getElementById('btn-lang-onboard-en');
      const dbMs = document.getElementById('btn-lang-dash-ms');
      const dbEn = document.getElementById('btn-lang-dash-en');
      const landMs = document.getElementById('btn-lang-land-ms');
      const landEn = document.getElementById('btn-lang-land-en');

      if (landMs && landEn) {
        landMs.className = lang === 'ms' ? "px-2 py-1 rounded-lg bg-white text-pastel-600 shadow-sm transition" : "px-2 py-1 rounded-lg text-slate-500 hover:text-slate-800 transition";
        landEn.className = lang === 'en' ? "px-2 py-1 rounded-lg bg-white text-pastel-600 shadow-sm transition" : "px-2 py-1 rounded-lg text-slate-500 hover:text-slate-800 transition";
      }'''
assert old_switch_lang in content, "old_switch_lang not found"
content = content.replace(old_switch_lang, new_switch_lang, 1)

# 7. Add landing page JavaScript functions and update screen switching
old_screens = '''      if (currentFamilyId) {
        showDashboardScreen();
      } else {
        showOnboardingScreen();
      }
    }

    function showOnboardingScreen() {
      document.getElementById('screen-onboarding').classList.remove('hidden');
      document.getElementById('screen-dashboard').classList.add('hidden');
    }

    function showDashboardScreen() {
      document.getElementById('screen-onboarding').classList.add('hidden');
      document.getElementById('screen-dashboard').classList.remove('hidden');'''

new_screens = '''      if (currentFamilyId) {
        showDashboardScreen();
      } else {
        showLandingScreen();
      }
    }

    function showLandingScreen() {
      const landEl = document.getElementById('screen-landing');
      if (landEl) landEl.classList.remove('hidden');
      document.getElementById('screen-onboarding').classList.add('hidden');
      document.getElementById('screen-dashboard').classList.add('hidden');
      window.scrollTo({ top: 0, behavior: 'smooth' });
      if (window.lucide && lucide.createIcons) lucide.createIcons();
    }

    function showOnboardingScreen(initialRole = 'mother') {
      const landEl = document.getElementById('screen-landing');
      if (landEl) landEl.classList.add('hidden');
      document.getElementById('screen-onboarding').classList.remove('hidden');
      document.getElementById('screen-dashboard').classList.add('hidden');
      switchAuthTab(initialRole);
      window.scrollTo({ top: 0, behavior: 'smooth' });
      if (window.lucide && lucide.createIcons) lucide.createIcons();
    }

    function showDashboardScreen() {
      const landEl = document.getElementById('screen-landing');
      if (landEl) landEl.classList.add('hidden');
      document.getElementById('screen-onboarding').classList.add('hidden');
      document.getElementById('screen-dashboard').classList.remove('hidden');'''
assert old_screens in content, "old_screens not found"
content = content.replace(old_screens, new_screens, 1)

# 8. Add previewLandingPhase and toggleFaq functions
old_switch_auth = '''    // ONBOARDING TAB TOGGLE
    function switchAuthTab(role) {'''

new_faq_funcs = '''    // ==========================================
    // LOGIK INTERAKTIF LANDING PAGE
    // ==========================================
    function previewLandingPhase(phase) {
      const btnTtc = document.getElementById('prev-btn-ttc');
      const btnPreg = document.getElementById('prev-btn-preg');
      const btnBaby = document.getElementById('prev-btn-baby');
      const cardTtc = document.getElementById('prev-card-ttc');
      const cardPreg = document.getElementById('prev-card-preg');
      const cardBaby = document.getElementById('prev-card-baby');

      if (!btnTtc || !btnPreg || !btnBaby) return;

      const activeClass = "flex-1 py-1.5 rounded-lg text-center transition bg-white text-pastel-700 shadow-sm font-bold";
      const inactiveClass = "flex-1 py-1.5 rounded-lg text-center transition text-slate-500 font-medium hover:text-slate-800";

      btnTtc.className = phase === 'ttc' ? activeClass : inactiveClass;
      btnPreg.className = phase === 'preg' ? activeClass : inactiveClass;
      btnBaby.className = phase === 'baby' ? activeClass : inactiveClass;

      if (cardTtc) cardTtc.classList.toggle('hidden', phase !== 'ttc');
      if (cardPreg) cardPreg.classList.toggle('hidden', phase !== 'preg');
      if (cardBaby) cardBaby.classList.toggle('hidden', phase !== 'baby');
    }

    function toggleFaq(index) {
      const ans = document.getElementById('faq-ans-' + index);
      const icon = document.getElementById('faq-icon-' + index);
      if (!ans) return;
      const isHidden = ans.classList.contains('hidden');
      if (isHidden) {
        ans.classList.remove('hidden');
        if (icon) icon.style.transform = 'rotate(180deg)';
      } else {
        ans.classList.add('hidden');
        if (icon) icon.style.transform = 'rotate(0deg)';
      }
    }

    // ONBOARDING TAB TOGGLE
    function switchAuthTab(role) {'''
assert old_switch_auth in content, "old_switch_auth not found"
content = content.replace(old_switch_auth, new_faq_funcs, 1)

# Write back to index.html
with open(html_path, 'w', encoding='utf-8') as f:
    f.write(content)

# Update sw.js version
with open(sw_path, 'r', encoding='utf-8') as f:
    sw_content = f.read()
sw_content = re.sub(r"const CACHE_NAME = 'bukupinkku-v\d+';", "const CACHE_NAME = 'bukupinkku-v37';", sw_content)
with open(sw_path, 'w', encoding='utf-8') as f:
    f.write(sw_content)

print("Landing page integrated successfully! Service worker updated to bukupinkku-v37.")
