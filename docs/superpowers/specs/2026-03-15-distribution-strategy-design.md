# Maestro Distribution Strategy

## Overview

Maestro is a native macOS app that lets non-technical users manage software projects using AI agents. This document defines the business model, packaging, positioning, marketing, and sticky features strategy.

**Chosen approach:** Premium Mac App, source-available with Business Source License (BSL), sold as signed builds.

**Core thesis:** The code is public on GitHub for career credibility and developer discovery. Revenue comes from selling signed, notarized builds to non-technical users who will never compile from source. Two audiences (developers who admire, non-devs who buy) feed two funnels that reinforce each other.

---

## Business Model & Pricing

**License:** Business Source License (BSL 1.1)

- Source code is public on GitHub, readable and forkable
- Commercial use (selling a competing product) is restricted
- Converts to Apache 2.0 after 3 years
- Individual use, modification, and contributions are allowed

**Pricing:**

- $49 one-time purchase for signed, notarized, auto-updating builds
- Free major version upgrades for 1 year from purchase date
- After 1 year, major version upgrades are $29
- No subscription, no account required, no telemetry
- 3-day free trial, full-featured, no credit card
- Requires a Claude/Anthropic API key (usage-based, typically $5-20/month depending on usage). Maestro guides users through setup on first launch.
- After trial expires: app enters read-only mode (view projects, export code, see history) but cannot run new agent tasks. No work is held hostage.

---

## Packaging & Distribution

**Build & delivery:**

- Signed and notarized .dmg via Apple Developer Program
- Auto-updates via Sparkle framework
- License key activation -- no account creation, no login
- Payment processing via Paddle or Lemon Squeezy (handles license keys, tax, receipts, refunds)

**Why not the Mac App Store:**

- Maestro is non-sandboxed (needs to spawn Claude CLI) -- App Store won't allow it
- Higher revenue retention (~92-95% via Paddle/Lemon Squeezy vs. 70-85% via App Store)
- Direct customer relationship (email list, upgrade offers)

**Website:**

- Simple landing page: hero demo GIF, 3 value props, pricing, download button
- Single-page site (Astro, Next.js, Carrd, or Framer)
- Domain: TBD (check availability for maestro-related .dev/.app domains)

**GitHub repo:**

- Clean README with demo GIF, feature list, "Download" CTA linking to site
- BSL 1.1 license file
- Contributing guide
- Issues and discussions enabled
- Build instructions for compiling from source (acceptable leakage -- target buyers are non-technical and won't self-compile; auto-updates, notarization, and ease of install are the moat, not access restriction)

---

## Target Audience

People who know what they want built but can't build it themselves:

- Non-technical founders building MVPs
- Designers who want to prototype beyond Figma
- Small business owners who need custom software but can't afford a developer
- Technical-adjacent people (data analysts, product managers) who want to build their own tools

---

## Positioning & Messaging

**One-liner:** "Manage software projects with AI agents -- no coding required."

**Core message framework:**

| What they feel | What Maestro says |
|---|---|
| "I have an idea but can't code" | "Describe your tasks, let AI agents build it" |
| "AI tools are confusing" | "Visual board -- drag tasks, watch progress, no terminal" |
| "I don't trust black-box AI" | "Source-available, runs locally, everything on your machine" |
| "Hiring a dev is expensive" | "Your AI dev team for $49 -- just add API credits" |

**Differentiators:**

- vs. Cursor/Windsurf/Claude Code: Those are for developers. Maestro is for everyone else.
- vs. no-code tools (Bubble, Webflow): Those constrain you to their platform. Maestro produces real code you own.
- vs. ChatGPT/Claude chat: Those are conversations. Maestro is a project -- structured, persistent, visual.

**Tone:** Confident, approachable, zero jargon. Never say "orchestration," "agent pool," or "async concurrency" in marketing. Say "AI workers," "your team of AI builders," "watch them work."

---

## Marketing & Launch Strategy

**Phase 1 -- Launch:**

- ProductHunt launch as the main event
- Demo video (60-90s) ready for launch day
- Landing page live with pricing and download
- GitHub repo public with clean README
- Post to X/Twitter, r/startups, r/entrepreneur, r/nocode, r/SideProject
- "Why I built this" blog post on Hacker News (targets the "developers who admire" funnel for GitHub stars and awareness -- not a direct revenue channel)

**Phase 2 -- Ongoing:**

- Short-form video content -- screen recordings of Maestro building things from scratch. Best content format for non-dev audiences.
- SEO blog posts targeting "build an app without coding" type queries
- Community engagement (Indie Hackers, no-code forums, founder communities)

---

## Sticky Features

### Data gravity -- your projects live here

- **Project history & agent logs:** Every agent run, every change, every decision recorded. Months of project context that doesn't exist anywhere else.
- **Cost tracking dashboard:** "You've spent $14.20 in API credits this month across 3 projects." Users who track spending through Maestro won't want to lose that visibility.

### Workflow lock-in -- it becomes how you work

- **Templates:** Save a project setup as a template ("Landing page," "Chrome extension," "REST API"). Once someone has 5-10 templates dialed in, they're not starting over elsewhere.
- **Prompt library:** Saved instructions that tune how agents approach work ("Always use Tailwind," "Write tests first"). Personal prompt refinement over time is extremely sticky.

### Trust & comfort -- it feels safe

- **Visual diff viewer:** Before accepting agent work, see exactly what changed in a simple side-by-side view. Non-devs need this to feel in control.
- **Undo / rollback:** One-click revert any agent run. Safety net that makes non-devs brave enough to keep using it.

### Delight -- it feels magic

- **Progress narration:** Instead of raw terminal output, Maestro translates agent work into plain English: "Creating the login page... Adding the signup form... Writing tests..."
- **Project timeline:** Visual story of how your project evolved. "Day 1: Created homepage. Day 3: Added user authentication. Day 7: Launched." Becomes a personal artifact people are proud of.

---

## Support

- **Primary channel:** GitHub Discussions (free, public, searchable, builds community)
- **Secondary:** Email support (best-effort, no SLA)
- **Self-serve:** In-app help for common tasks (API key setup, project configuration, understanding agent output)
- Support is included in the $49 price. Premium/priority support is a potential future upsell but not at launch.
