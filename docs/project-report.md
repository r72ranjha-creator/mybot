# MyBot — Project Report

**Tarikh:** 26 October 2026
**App:** MyBot (`com.mybot.assistant`) — personal Android AI assistant
**Repo:** github.com/r72ranjha-creator/mybot (private)
**Ye report:** kya bana, kya nahi bana, kaise chalana hai, aur aage kya karna hai.

---

## 1. Ek nazar mein

Is build mein MyBot ke saath **voice, photo, file, research (sources ke sath),
projects, internal search aur crypto mode** jud gaye hain — aur **Buy/Sell
button dabane ki ijazat** bhi, magar sakht guardrails ke saath.

Jo cheezein **is build mein nahi** aayi: **video**, **scheduled research**,
aur **PDF/Markdown export ka button**. Wajah neeche §6 mein saaf likhi hai —
ye kaam adhoora chhoda nahi gaya, jaan bujh kar agli build ke liye rakha gaya
hai, kyunki in teenon ke liye naye native plugins chahiye aur is waqt mere
paas asli phone par test karne ka koi zariya nahi hai.

---

## 2. Ab kya kya kaam karta hai

### Voice
- Chat mein **mic button** — bol kar command dein.
- Phone ki speech engine se Urdu / English / Hindi (Urdu bolne ke liye qareeb
  tareen model) — jo zubaan phone mein maujood ho, wohi chunti hai aur screen
  par dikhati hai.
- Roman Urdu ka koi speech model duniya mein nahi hai; is liye bolne ki
  transcription ko **usi command parser** se guzara jata hai jo typing se
  guzarta hai. Natija: bol kar diya gaya command aur likha gaya command bilkul
  ek hi plan banate hain.
- **Speaker button** — jawab sunne ke liye. Lamba jawab jumla jumla kar ke
  bolta hai. Urdu voice na mile to ek line mein bata deta hai.
- **Mute/unmute** — ek tap, setting save rehti hai.

### Photo
- Gallery se **ek se chhe tasveerain**, ya camera se photo.
- Bhejne se pehle preview strip — har attachment hataya ja sakta hai.
- Tasveerain phone ke andar app ki private storage mein rakhi jati hain
  (gallery mein copy nahi hotin), aur delete bhi ho sakti hain.
- Vision model se sawal: "is photo mein kya hai", "is chart ka trend batao",
  "is receipt ka total nikalo" — sab chalte hain. Ek waqt mein 4 tasveerain
  model ko jati hain, har ek `[photo 1]` ki tarah label hoti hai.

### File
- PDF, TXT, MD, CSV, XLSX/XLS.
- **PDF** phone par parse nahi hota — poora PDF seedha model ko document ki
  tarah bheja jata hai (Gemini / OpenAI / Anthropic teenon ye samajhte hain).
  Faida: scanned PDF bhi parh li jati hai. Nuqsan: har call thori bhaari hoti hai.
- **CSV / Excel** phone par parh kar text banaya jata hai: columns, rows,
  sample data — is liye "total nikalo" jaisa sawal theek jawab deta hai.
- File ka size aur naam preview mein dikhta hai.

### Research (sources ke sath)
- Chat composer mein **Research / Deep Research / Think Deeply**.
- Search providers: **Tavily (default) → Perplexity → Brave → Serper**, apne
  aap fallback. Jo provider jawab de, wo screen par likha jata hai.
- Keys **AI Settings → Search providers** mein daali jati hain, wahi Keystore
  jahan model keys hain — SQLite mein nahi, logs mein nahi, backup mein nahi.
- **Har research jawab ke neeche Sources** ka block: number, title, domain,
  date, one-line summary, aur **High / Medium / Low trust badge**.
- Trust filter: sarkari/taleemi domains, bade news houses, exchanges, GitHub,
  official docs → High. Content farms aur bina tareekh wale ajnabi domains → Low.
  Duplicate sources hata diye jate hain.
- Agar koi bhi source bharosay ke qabil na ho: jawab bas
  **"Reliable source nahi mila."**
- Jawab mein jo `[3]` likha ho magar source list mein teesra source na ho — aisa
  nahi ho sakta, citations check hoti hain.

### Deep Research
1. Sawal ko 3–8 chhoti searches mein toda jata hai.
2. Har search ke behtareen results liye jate hain.
3. Duplicate aur kamzor sources hata kar top 8–12 pages parhe jate hain.
4. Jawab fixed structure mein likha jata hai: **Executive summary → Key
   findings → Detailed analysis → Pros & cons → Risks → Comparison table →
   Conclusion → Sources**.
5. Report save hoti hai, us project ke saath jodi jati hai, aur apne records
   mein searchable ho jati hai.

### Projects
- Projects screen: naya project, naam, tafseel, aur **custom instructions**
  (Manager Bot unhe follow karta hai).
- Project ke andar: chats, reports, files — sab alag.
- Project chun kar chat karein to us ka context jawab mein shamil hota hai.

### Crypto Research Mode
- Kisi bhi coin/protocol ke liye: latest news, official updates, GitHub
  activity, listing news, token unlocks, aur bullish/bearish factors.
- Har report ke sath sources, aur neeche permanent line:
  *"Ye financial advice nahi hai. MyBot trade nahi karta."*

### Internal knowledge search
- Aap ke apne chats, reports, notes aur file text par full-text search.
- "Maine pichlay hafte BTC ke baare mein kya likha tha" → apne records se jawab.
- "Meri pichli trades ka pattern" → journal par sawal: kitne signals, kis
  symbol par zyada, average confidence, long/short ka hissa.

### Buy/Sell button (naya)
Aap ke kehne par MyBot TradingView ka Buy/Sell button **khud daba sakta hai** —
magar pandit shartein:

1. **Setting band hai by default.** Settings → Trading mein on karna padta hai,
   aur on karte waqt ek warning parh kar confirm karna padta hai.
2. Screen **TradingView** honi chahiye, aur screenshot **20 second se purana
   nahi** hona chahiye.
3. Vision model screenshot parh kar confirm karta hai ke jo button dikh raha
   hai wo aap ke maange hue side ka hai (Buy/Long ya Sell/Short), aur order
   form par wohi symbol hai.
4. **Har press ke liye alag approval** — ek approval = ek press. Koi "yaad
   rakhna" nahi.
5. Press ke baad **screenshot save** hota hai, taake record rahe.

Kabhi nahi hoga: schedule se press, ek plan mein do press, 60 second ke andar
dobara press, ya phone lock hone par press.

---

## 3. Database

Purane tables waise hi hain — kuch delete nahi hua, kuch badla nahi gaya.
Naye tables: `media_files`, `chat_attachments`, `projects`, `project_files`,
`research_reports`, `research_sources`, `research_queries`, `source_ratings`,
`saved_links`, `scheduled_research`, `user_notes`, aur ek full-text index
(`internal_fts`). `chat_messages` mein do naye column: `project_id`,
`attachment_count`. Purana data update ke baad bhi wahin rahega.

---

## 4. Saboot (jo main ne khud chalaya)

| Cheez | Natija |
|---|---|
| `flutter analyze` | **0 error, 0 warning** (21 style notes) |
| `flutter test` | **13/13 pass** |
| `flutter build apk --release` | **63.3 MB APK bana** |
| APK check | package `com.mybot.assistant`, minSdk 26, RECORD_AUDIO + CAMERA permissions, app label MyBot |
| Signing | `CN=MyBot Release`, wohi key jo pehle thi — update seedha oopar install hoga |
| GitHub Actions | har push par naya **MyBot-APK** artifact |

---

## 5. Kaise chalayein (pehli baar)

1. Naya APK install karein (purana uninstall karne ki zaroorat nahi, signing
   key wohi hai).
2. **Settings → Accessibility → MyBot automation** on karein.
3. **More → AI settings**: ek model key (Gemini / OpenAI / Anthropic /
   OpenRouter).
4. **AI settings → Search providers**: Tavily ki key (research ke liye). Is ke
   bagair baqi sab chalta hai, sirf research band rehta hai — app saaf bata deta hai.
5. **Settings → Trading**: agar Buy/Sell dabana chahte hain to yahan on karein.
6. Chat mein: mic dabayein ya likhein — "BTC ki latest news research karo",
   "is chart ka trend batao" (photo ke sath), "meri pichli trades ka pattern".

---

## 6. Jo is build mein nahi hai (aur kyun)

| Cheez | Halat | Wajah |
|---|---|---|
| **Video** (upload, record, key frames, compress) | Nahi bana | Key-frame nikalne aur compress karne ke liye native plugins chahiye. Is build mein 3 plugins ne build tor di (file_picker ka purana version, pdf_text jo AGP 9 par chalta hi nahi, aur ek Gradle OOM). Bina phone test kiye chautha native plugin daalna wahi risk dobara lena hota. |
| **Scheduled research** (roz 8 baje brief) | Table bani, runner nahi | `workmanager` + notifications chahiye — dono native, aur phone sote waqt ka behaviour bina device test kiye verify nahi ho sakta. |
| **PDF / Markdown export ka button** | Data tayyar hai, button nahi | Report ka markdown maujood hai; file likhne aur share karne ka UI agli build mein. |
| **Follow-up ka button** | Engine mein parent-report chaining maujood hai | UI mein "isko follow-up banao" ka control nahi. |
| **Screenshot OCR (alag se)** | Vision model se hota hai | Text parhne ke liye alag OCR engine nahi lagaya; model parhta hai aur text ko search index mein daal deta hai. |

Ye chaar cheezein **aglay build** ka kaam hain, aur tarteeb ye hai:
1. Scheduled research (sab se zyada faida, kam risk)
2. Export (PDF + Markdown + share)
3. Follow-up button
4. Video (sab se aakhir, kyunki sab se bhaari)

---

## 7. Sach jo batana zaroori hai

- **App abhi tak kisi asli phone par nahi chala.** Jo bhi upar likha hai wo
  build, analyze aur unit test ka saboot hai — chalte hue app ka nahi. Pehli
  baar aap chala rahe hain, aur jo masla aaye wo mujhe batana sab se qeemti
  cheez hogi.
- **APK 57 MB se 63 MB ho gaya** hai naye plugins ki wajah se.
- **Urdu voice** phone ki speech engine par depend karta hai. Kuch phones mein
  Urdu voice nahi hoti — app bata deta hai, chup nahi rehta.
- **Buy/Sell ki ijazat** asli paisa hila sakti hai. Guardrails ghalti ka asar
  kam karte hain, khatam nahi. Jab chahein Settings se band kar dein.
