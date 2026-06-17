# Build Prompt — PeTender Showcase Website

> Paste this whole file to an AI coding agent (or hand it to a web developer) as the brief for building a marketing/showcase website for the **PeTender** mobile app. Everything below is factual to the actual app — do not invent features that aren't listed here.

---

## 1. Your task

Build a polished, responsive **single-page showcase website** for *PeTender*, a pet-care job-board mobile app. The site's job is to explain what the app does, show it off with screenshots, and look professional enough to headline a university final-project portfolio. It is **marketing/informational only** — no backend, no login, no live app data.

**Default stack** (change only if the requester says otherwise): a static site in plain **HTML + CSS + a little vanilla JS**, or **React + Vite + Tailwind** if a component approach is preferred. No CMS. Must deploy cleanly to GitHub Pages / Netlify / Vercel as static files.

---

## 2. The product (accurate description)

**PeTender** connects **pet owners** who need care for their pets with **pet sitters** looking for work — a focused "job board for pet care." Built for the **Taiwan** market (UTC+8, prices in **TWD**).

A single account can act as an **Owner**, a **Sitter**, or **Both**, and the app adapts its navigation to the chosen role.

**The core loop:**
1. An owner **posts a job** (pet type, breed, photo, schedule, pay rate, map location).
2. Sitters **browse/search** jobs and **apply**.
3. The owner reviews applicants and **accepts** one (others are auto-declined).
4. The sitter does the work and **marks it done**.
5. The owner **confirms completion and rates** the sitter 1–5 stars.

---

## 3. Feature list (use these for the "Features" section — all real)

- **Role-adaptive experience** — Owner, Sitter, or Both; the UI and center tab change to match.
- **Job feed & search** — browsable home feed with pet-type filter chips (Dog / Cat / Other), keyword search, and advanced filters (pay-rate range, earliest start date). Pull-to-refresh throughout.
- **Post a job** — photo upload, **breed autocomplete** (powered by The Dog API / The Cat API), date & time picker, hourly pay rate in TWD, and a **Google Maps location picker** (tap or drag a pin).
- **Rich job details** — hero photo, embedded **Google Map**, owner profile, and one-tap **bookmarking** (saved locally).
- **Application lifecycle** — apply → accepted → in-progress → awaiting confirmation → completed, each with clear status badges.
- **Ratings & reviews** — owners rate sitters on completion; a running star average shows on the sitter's profile.
- **Breed Explorer** — a browsable encyclopedia of **dog and cat breeds** with search, photo galleries, temperament tags, and (for cats) animated trait bars like energy, affection, and grooming. Data from The Dog API, The Cat API, and dog.ceo.
- **Profiles** — avatar, bio, role, activity stats (jobs posted / applied / completed / bookmarks), editable details.
- **Local notifications** — a reminder 24 hours before an accepted job starts (Asia/Taipei timezone).
- **Personalization** — **dark mode**, push-notification toggle, and language options (English / 繁體中文).

> ⚠️ Accuracy guardrails — do **not** claim: real-time chat, in-app payments, a web/desktop version, LINE login, or live availability. Sign-in is **email/password + Google** only. If you need filler, prefer "planned / roadmap" framing over fabricating shipped features.

---

## 4. Suggested page structure (single page, anchored nav)

1. **Sticky nav bar** — PeTender wordmark + 🐾, anchor links (Features · How it works · Breeds · Tech · Get the app), dark-mode toggle.
2. **Hero** — app name, one-line tagline (e.g. *"Find trusted care for your pets — or get paid to give it."*), two CTA buttons ("See features", "How it works"), and a phone mockup showing the home feed.
3. **Feature highlights** — a responsive grid of feature cards (icons + short copy) drawn from §3.
4. **How it works** — the 5-step loop from §2 as a numbered horizontal/vertical timeline, ideally split into an "Owner" track and a "Sitter" track.
5. **Screenshot gallery** — phone-framed screenshots in a carousel or staggered layout (Home, Job Detail, Post Job, Breed Explorer, Profile, Dark mode).
6. **Breed Explorer spotlight** — call out the dog/cat encyclopedia with a couple of sample breed cards.
7. **Tech stack** — logos/badges (see §6) showing this is a real, modern Flutter build.
8. **About / final-project note** — short paragraph framing it as a university final project, target market Taiwan.
9. **Footer** — credits, "Built with Flutter", links (GitHub repo placeholder), copyright.

---

## 5. Brand & design system (match the app exactly)

- **Primary (teal):** `#1D9E75`
- **Secondary (accent blue):** `#378ADD`
- **Style:** Material 3 / Material You — rounded corners (12–20px radius), soft elevation, generous whitespace, friendly but clean.
- **Light & dark themes:** ship both; the dark-mode toggle must actually work and persist (localStorage).
- **Typography:** a rounded, friendly sans-serif (e.g. Nunito, Poppins, or Inter). Large, confident headings.
- **Motif:** paws 🐾 and pets; warm and trustworthy, not corporate. Subtle scroll-reveal / fade-in animations (mirroring the app's staggered fade+slide), but keep it tasteful and performant.
- **Imagery:** use pet photography placeholders and phone-frame mockups for screenshots.

---

## 6. Tech-stack badges to display (the app's real stack)

- **Flutter** (3.x) · **Dart** (3) · **Material 3**
- **Provider** (state management)
- **Backendless** (REST backend, auth + data)
- **Google Maps** · **Google Sign-In**
- **The Dog API** · **The Cat API** · **dog.ceo**
- Local notifications, timezone-aware (Asia/Taipei)
- Target platforms: **Android** (min SDK 23) and **iOS** (14+)

---

## 7. Technical requirements

- **Responsive:** mobile-first; must look great on phone, tablet, and desktop.
- **Accessible:** semantic HTML, alt text on all images, keyboard-navigable nav, WCAG AA color contrast (verify the teal/white combos).
- **Performance:** lazy-load gallery images, no heavy frameworks for a static page, Lighthouse 90+ on performance & accessibility.
- **SEO basics:** title, meta description, Open Graph tags + a social share image.
- **Self-contained:** all assets local or via CDN; document any external fonts/icons used.
- **Clean structure:** organized files, commented CSS variables for the color tokens above so they're easy to retheme.

---

## 8. Assets the requester must provide (leave tagged placeholders if missing)

- App screenshots (Home, Job Detail, Post Job, Breed Explorer, Profile, dark mode).
- App logo / icon (use a 🐾 + "PeTender" wordmark placeholder until supplied).
- Any real GitHub repo or download links (use `#` placeholders otherwise).

---

## 9. Copy tone

Warm, reassuring, and concise. Speak to two audiences in parallel — worried pet owners ("trusted care, nearby") and sitters wanting flexible income ("get paid to spend time with pets"). Avoid jargon in the marketing copy; save the technical detail for the Tech section.

---

## 10. Deliverables

1. The complete website source (HTML/CSS/JS or React project).
2. A short `README` with: how to run locally, how to deploy, and where to drop in real screenshots/links.
3. Both light and dark themes working, with a persistent toggle.

When done, summarize what was built and list every spot where placeholder assets/links still need to be replaced.
