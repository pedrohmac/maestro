# Maestro Landing Page Design

## Overview

Single-page marketing site for Maestro at **usemaestro.dev**. Targets non-technical users (founders, designers, small business owners) who want to build software with AI agents but can't code. The site sells a $49 one-time purchase Mac app distributed as a signed .dmg.

**Tech stack:** Astro (static site generator), deployed to Vercel/Netlify/Cloudflare Pages.

**Repo:** `maestro-site`, sibling to the main `maestro` repo.

---

## Design Language

- **Theme:** Dark background, light text — mirrors the macOS app aesthetic
- **Accent color:** Indigo (#6366f1) for CTAs, highlights, and interactive elements
- **Typography:** System font stack (-apple-system, BlinkMacSystemFont, etc.) for fast load and native feel
- **Tone:** Confident, approachable, zero jargon. Say "AI workers" not "agent orchestration"
- **No emojis** — clean, professional presentation throughout
- **Responsive:** Desktop-first (Mac app buyers are on desktop), but mobile-friendly for social traffic

---

## Page Structure

### 1. Navigation (sticky)

Fixed top bar with:
- **Left:** "Maestro" wordmark
- **Center/Right:** Anchor links — How it works, Pricing, FAQ, GitHub (external)
- **Right:** "Download" CTA button (indigo)

Simple, no hamburger menu needed — few enough links to show inline. On mobile, links collapse or stack.

### 2. Hero Section

The first thing visitors see. Must answer "what is this and why should I care" in 3 seconds.

- **Badge:** "For macOS" — small uppercase label, sets platform expectation immediately
- **Headline:** "Manage software projects with AI agents"
- **Subline:** "Describe your tasks. Watch AI build it. No coding required."
- **Two CTAs:**
  - Primary: "Download Free Trial" (indigo button, links to .dmg download or Lemon Squeezy placeholder)
  - Secondary: "Watch Demo" (outline button, scrolls to or opens demo video — placeholder until real video exists)
- **Animated demo area:** CSS/JS animation that simulates the app's kanban board. Shows:
  - A kanban board with Todo / In Progress / Review / Done columns
  - Task cards sliding from Todo to In Progress
  - A simulated agent activity indicator (pulsing dot, progress text)
  - Cards moving to Done
  - Loops continuously
  - This gets replaced with a real screen recording/GIF later

### 3. Value Propositions

Three cards in a row, derived from the messaging framework in the distribution strategy:

| Card | Title | Description |
|------|-------|-------------|
| 1 | Visual Project Board | Drag tasks, watch progress. No terminal, no jargon. |
| 2 | AI Workers, Not Chat | Assign tasks to AI agents that build real code autonomously. |
| 3 | Private & Local | Runs on your Mac. Your code stays on your machine. |

Cards are simple: title + short description. No icons or emojis. Clean typography does the work.

### 4. How It Works

Three-step horizontal flow with numbered circles and arrows between them:

1. **Describe** — Write what you want in plain English
2. **Dispatch** — AI agents pick up tasks and start building
3. **Review** — See what changed, approve or roll back

Each step has a number badge (indigo circle), title, and one-line description. Connected by arrow indicators.

### 5. Pricing

Single centered card — no tiers, no comparison table. One product, one price.

- **Price:** $49 (large, bold)
- **Subtitle:** "One-time purchase. No subscription."
- **Feature list** (plain text, no bullets or checkmarks):
  - 3-day free trial, full-featured
  - Free updates for 1 year
  - No account required
  - No telemetry or tracking
  - Source-available on GitHub
- **CTA:** "Download Free Trial" button
- **Note below card:** "Requires a Claude API key (typically $5-20/month). Maestro guides you through setup."

### 6. FAQ

Static list of questions and answers (no accordion/toggle — the page is short enough to show all answers). Addresses objections before they become blockers:

| Question | Answer |
|----------|--------|
| Do I need to know how to code? | No. Maestro is designed for non-developers. You describe what you want, AI agents write the code. |
| What does the AI API cost? | Maestro uses Claude by Anthropic. API usage typically costs $5-20/month depending on how much you build. Maestro guides you through setup on first launch. |
| Is my code private? | Yes. Everything runs locally on your Mac. Your code never leaves your machine. |
| What happens after the trial? | The app enters read-only mode. You can still view your projects, export code, and see history. No work is held hostage. Purchase to keep building. |
| Can I build [X] with this? | If a developer could build it, Maestro's AI agents can attempt it. Best for web apps, APIs, scripts, and tools. |
| What if I need help? | Support via GitHub Discussions and email. Community-driven, searchable, and free. |

### 7. Footer

Minimal. Two-column layout:
- **Left:** "2026 Maestro"
- **Right:** GitHub, Support, Privacy (links)

---

## Animated Hero Demo

Since no real screen recording exists yet, build a CSS/JS animation that sells the concept:

**What it shows:**
1. A simplified kanban board (4 columns: Todo, In Progress, Review, Done)
2. 3-4 task cards with realistic titles (e.g., "Add login page", "Create API endpoint", "Write landing page")
3. Animation sequence (loops):
   - Cards sit in Todo
   - One card slides to In Progress, a small pulsing indicator appears ("Agent working...")
   - After a beat, the card slides to Review
   - Another card starts moving to In Progress simultaneously
   - Cards move to Done
   - Reset and loop

**Implementation:** Pure CSS animations with `@keyframes`. No JS library needed. Lightweight, performant, no layout shift.

**Styling:** Simplified version of the real app's kanban — same dark theme, indigo accents, card shapes. Not pixel-perfect reproduction, just enough to convey the concept.

---

## Technical Details

### Project Structure

```
maestro-site/
  src/
    pages/
      index.astro        # Single page
    components/
      Nav.astro           # Sticky navigation
      Hero.astro          # Hero with animated demo
      ValueProps.astro    # Three value prop cards
      HowItWorks.astro   # Three-step flow
      Pricing.astro       # Pricing card
      FAQ.astro           # Question/answer list
      Footer.astro        # Footer
      KanbanDemo.astro    # Animated kanban demo component
    styles/
      global.css          # CSS variables, reset, base styles
    layouts/
      Layout.astro        # HTML shell, meta tags, font loading
  public/
    favicon.svg           # Maestro icon
    og-image.png          # Open Graph image for social sharing
  astro.config.mjs
  package.json
```

### Deployment

- Static output (`output: 'static'` in Astro config)
- Deploy to Vercel, Netlify, or Cloudflare Pages — all have Astro adapters
- Custom domain: usemaestro.dev
- No server-side rendering needed — pure static HTML/CSS

### SEO & Meta

- Title: "Maestro — Manage software projects with AI agents"
- Description: "Describe your tasks, let AI agents build it. Visual project board for non-developers. $49 one-time, runs locally on your Mac."
- Open Graph image: screenshot or stylized graphic of the app
- Canonical URL: https://usemaestro.dev

### Performance Targets

- Zero JavaScript by default (Astro's strength)
- The kanban animation uses CSS `@keyframes` only — no JS runtime
- Total page weight under 100KB
- Lighthouse score: 95+ across all categories

### External Links

- Download button: placeholder URL (Lemon Squeezy product page, to be set up later)
- GitHub: link to the maestro repo (to be made public)
- Support: link to GitHub Discussions
- Privacy: simple privacy policy page (can be a second Astro page or external)

---

## What's NOT in Scope

- **No blog** — can be added post-launch as a second Astro page collection
- **No analytics** — no telemetry aligns with the app's values. Can add privacy-respecting analytics (Plausible, Fathom) later if needed.
- **No payment integration** — the buy button links to Lemon Squeezy (external). No checkout flow on the site itself.
- **No real demo video** — the animated hero is the placeholder. Real video is a separate production effort.
- **No dark/light mode toggle** — dark only, matches the app
