# Maestro Landing Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a static single-page marketing site for Maestro at usemaestro.dev using Astro.

**Architecture:** Astro static site with one page composed of 7 Astro components (Nav, Hero, ValueProps, HowItWorks, Pricing, FAQ, Footer) plus a KanbanDemo component for the animated hero. All styling via a single global CSS file using CSS custom properties. Zero JavaScript in production — the kanban animation is pure CSS `@keyframes`.

**Tech Stack:** Astro 5, CSS custom properties, CSS @keyframes animations

---

### Task 1: Scaffold Astro Project

**Files:**
- Create: `/Users/pedrohm/workspace/projects/maestro-site/package.json`
- Create: `/Users/pedrohm/workspace/projects/maestro-site/astro.config.mjs`
- Create: `/Users/pedrohm/workspace/projects/maestro-site/tsconfig.json`
- Create: `/Users/pedrohm/workspace/projects/maestro-site/.gitignore`

- [ ] **Step 1: Create project directory and initialize**

```bash
mkdir -p /Users/pedrohm/workspace/projects/maestro-site
cd /Users/pedrohm/workspace/projects/maestro-site
npm init -y
npm install astro@latest
```

- [ ] **Step 2: Create astro.config.mjs**

```javascript
// astro.config.mjs
import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://usemaestro.dev',
  output: 'static',
});
```

- [ ] **Step 3: Create tsconfig.json**

```json
{
  "extends": "astro/tsconfigs/strict"
}
```

- [ ] **Step 4: Create .gitignore**

```
node_modules/
dist/
.astro/
.DS_Store
```

- [ ] **Step 5: Create directory structure**

```bash
mkdir -p src/pages src/components src/styles src/layouts public
```

- [ ] **Step 6: Initialize git repo**

```bash
cd /Users/pedrohm/workspace/projects/maestro-site
git init
git add -A
git commit -m "chore: scaffold Astro project"
```

- [ ] **Step 7: Verify Astro builds**

```bash
npx astro build
```

Expected: Build succeeds (may warn about no pages yet, that's fine).

---

### Task 2: Global Styles and Layout Shell

**Files:**
- Create: `src/styles/global.css`
- Create: `src/layouts/Layout.astro`
- Create: `src/pages/index.astro` (minimal placeholder)

- [ ] **Step 1: Create global.css with CSS custom properties and reset**

```css
/* src/styles/global.css */

:root {
  --color-bg: #0a0a0f;
  --color-bg-subtle: rgba(255, 255, 255, 0.03);
  --color-bg-elevated: rgba(255, 255, 255, 0.06);
  --color-border: rgba(255, 255, 255, 0.08);
  --color-border-accent: rgba(99, 102, 241, 0.3);
  --color-text: #e4e4e7;
  --color-text-muted: rgba(255, 255, 255, 0.5);
  --color-text-faint: rgba(255, 255, 255, 0.35);
  --color-accent: #6366f1;
  --color-accent-hover: #818cf8;
  --color-accent-subtle: rgba(99, 102, 241, 0.15);
  --font-sans: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
  --max-width: 1080px;
  --nav-height: 56px;
}

*,
*::before,
*::after {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

html {
  scroll-behavior: smooth;
}

body {
  font-family: var(--font-sans);
  background: var(--color-bg);
  color: var(--color-text);
  line-height: 1.6;
  -webkit-font-smoothing: antialiased;
}

a {
  color: inherit;
  text-decoration: none;
}

img {
  max-width: 100%;
  display: block;
}

.container {
  max-width: var(--max-width);
  margin: 0 auto;
  padding: 0 24px;
}

section {
  padding: 80px 0;
}

@media (max-width: 768px) {
  section {
    padding: 48px 0;
  }
}
```

- [ ] **Step 2: Create Layout.astro with HTML shell and meta tags**

```astro
---
// src/layouts/Layout.astro
const title = "Maestro — Manage software projects with AI agents";
const description = "Describe your tasks, let AI agents build it. Visual project board for non-developers. $49 one-time, runs locally on your Mac.";
const canonicalURL = "https://usemaestro.dev";
---

<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>{title}</title>
    <meta name="description" content={description} />
    <link rel="canonical" href={canonicalURL} />

    <!-- Open Graph -->
    <meta property="og:type" content="website" />
    <meta property="og:url" content={canonicalURL} />
    <meta property="og:title" content={title} />
    <meta property="og:description" content={description} />
    <meta property="og:image" content={`${canonicalURL}/og-image.png`} />

    <!-- Twitter -->
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content={title} />
    <meta name="twitter:description" content={description} />
    <meta name="twitter:image" content={`${canonicalURL}/og-image.png`} />

    <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
  </head>
  <body>
    <slot />
  </body>
</html>

<style is:global>
  @import '../styles/global.css';
</style>
```

- [ ] **Step 3: Create minimal index.astro placeholder**

```astro
---
// src/pages/index.astro
import Layout from '../layouts/Layout.astro';
---

<Layout>
  <main>
    <p>Maestro site coming soon.</p>
  </main>
</Layout>
```

- [ ] **Step 4: Create placeholder favicon**

```bash
cat > public/favicon.svg << 'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
  <rect width="32" height="32" rx="6" fill="#6366f1"/>
  <text x="16" y="22" font-size="18" font-weight="bold" fill="white" text-anchor="middle" font-family="-apple-system, sans-serif">M</text>
</svg>
SVGEOF
```

- [ ] **Step 5: Build and verify**

```bash
npx astro build && npx astro preview
```

Expected: Site loads at localhost with dark background, placeholder text. Kill preview after verifying.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add layout shell, global styles, and index page"
```

---

### Task 3: Navigation Component

**Files:**
- Create: `src/components/Nav.astro`
- Modify: `src/pages/index.astro`

- [ ] **Step 1: Create Nav.astro**

```astro
---
// src/components/Nav.astro
const links = [
  { label: 'How it works', href: '#how-it-works' },
  { label: 'Pricing', href: '#pricing' },
  { label: 'FAQ', href: '#faq' },
  { label: 'GitHub', href: 'https://github.com/user/maestro', external: true },
];
---

<nav class="nav">
  <div class="nav-inner container">
    <a href="/" class="nav-logo">Maestro</a>
    <div class="nav-links">
      {links.map((link) => (
        <a
          href={link.href}
          class="nav-link"
          {...(link.external ? { target: '_blank', rel: 'noopener noreferrer' } : {})}
        >
          {link.label}
        </a>
      ))}
      <a href="#pricing" class="nav-cta">Download</a>
    </div>
  </div>
</nav>

<style>
  .nav {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    z-index: 100;
    height: var(--nav-height);
    background: rgba(10, 10, 15, 0.85);
    backdrop-filter: blur(12px);
    border-bottom: 1px solid var(--color-border);
  }

  .nav-inner {
    display: flex;
    align-items: center;
    justify-content: space-between;
    height: 100%;
  }

  .nav-logo {
    font-size: 18px;
    font-weight: 700;
    letter-spacing: -0.02em;
  }

  .nav-links {
    display: flex;
    align-items: center;
    gap: 24px;
  }

  .nav-link {
    font-size: 14px;
    color: var(--color-text-muted);
    transition: color 0.15s;
  }

  .nav-link:hover {
    color: var(--color-text);
  }

  .nav-cta {
    font-size: 14px;
    font-weight: 500;
    color: white;
    background: var(--color-accent);
    padding: 6px 16px;
    border-radius: 8px;
    transition: background 0.15s;
  }

  .nav-cta:hover {
    background: var(--color-accent-hover);
  }

  @media (max-width: 640px) {
    .nav-links {
      gap: 16px;
    }

    .nav-link {
      font-size: 13px;
    }
  }
</style>
```

- [ ] **Step 2: Add Nav to index.astro**

Replace the contents of `src/pages/index.astro`:

```astro
---
// src/pages/index.astro
import Layout from '../layouts/Layout.astro';
import Nav from '../components/Nav.astro';
---

<Layout>
  <Nav />
  <main style={`margin-top: var(--nav-height);`}>
    <p class="container">Sections go here.</p>
  </main>
</Layout>
```

- [ ] **Step 3: Build and verify**

```bash
npx astro build
```

Expected: Build succeeds. Navigation bar renders with links and download CTA.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add sticky navigation component"
```

---

### Task 4: Hero Section and Animated Kanban Demo

**Files:**
- Create: `src/components/Hero.astro`
- Create: `src/components/KanbanDemo.astro`
- Modify: `src/pages/index.astro`

- [ ] **Step 1: Create KanbanDemo.astro**

This is the pure-CSS animated kanban board that loops continuously.

```astro
---
// src/components/KanbanDemo.astro
---

<div class="kanban-demo" aria-hidden="true">
  <div class="kanban-board">
    <div class="kanban-col">
      <div class="kanban-col-header">Todo</div>
      <div class="kanban-card card-1">Add login page</div>
      <div class="kanban-card card-2">Create API endpoint</div>
      <div class="kanban-card card-3">Write landing page</div>
    </div>
    <div class="kanban-col">
      <div class="kanban-col-header">In Progress</div>
      <div class="kanban-card card-active">
        <span class="agent-dot"></span>
        Setting up project...
      </div>
    </div>
    <div class="kanban-col">
      <div class="kanban-col-header">Review</div>
    </div>
    <div class="kanban-col">
      <div class="kanban-col-header">Done</div>
    </div>
  </div>

  <!-- Overlay animation layer: cards that animate across columns -->
  <div class="kanban-anim-layer">
    <div class="anim-card anim-card-1">Add login page</div>
    <div class="anim-card anim-card-2">Create API endpoint</div>
  </div>
</div>

<style>
  .kanban-demo {
    position: relative;
    background: rgba(255, 255, 255, 0.02);
    border: 1px solid var(--color-border);
    border-radius: 16px;
    padding: 24px;
    overflow: hidden;
    max-width: 640px;
    margin: 0 auto;
  }

  .kanban-board {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 12px;
  }

  .kanban-col {
    min-height: 120px;
  }

  .kanban-col-header {
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--color-text-muted);
    margin-bottom: 8px;
    padding-bottom: 6px;
    border-bottom: 1px solid var(--color-border);
  }

  .kanban-card {
    background: var(--color-bg-elevated);
    border: 1px solid var(--color-border);
    border-radius: 6px;
    padding: 8px 10px;
    font-size: 12px;
    margin-bottom: 6px;
    color: var(--color-text);
  }

  .card-active {
    border-color: var(--color-border-accent);
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .agent-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--color-accent);
    animation: pulse 1.5s ease-in-out infinite;
    flex-shrink: 0;
  }

  /* Static cards fade in/out to simulate movement */
  .card-1 {
    animation: fade-out-card 8s ease-in-out infinite;
    animation-delay: 1s;
  }

  .card-2 {
    animation: fade-out-card 8s ease-in-out infinite;
    animation-delay: 3.5s;
  }

  .card-3 {
    opacity: 0.7;
  }

  /* Animated overlay cards */
  .anim-card {
    position: absolute;
    background: var(--color-bg-elevated);
    border: 1px solid var(--color-border-accent);
    border-radius: 6px;
    padding: 8px 10px;
    font-size: 12px;
    color: var(--color-text);
    opacity: 0;
    pointer-events: none;
    white-space: nowrap;
  }

  .anim-card-1 {
    animation: slide-across 8s ease-in-out infinite;
    animation-delay: 1s;
  }

  .anim-card-2 {
    animation: slide-across 8s ease-in-out infinite;
    animation-delay: 3.5s;
  }

  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.3; }
  }

  @keyframes fade-out-card {
    0%, 10% { opacity: 1; }
    15%, 60% { opacity: 0; }
    65%, 100% { opacity: 1; }
  }

  @keyframes slide-across {
    0% { top: 60px; left: 6%; opacity: 0; }
    5% { top: 60px; left: 6%; opacity: 1; }
    20% { top: 60px; left: 30%; opacity: 1; }
    40% { top: 60px; left: 55%; opacity: 1; }
    55% { top: 60px; left: 78%; opacity: 1; }
    60% { top: 60px; left: 78%; opacity: 0; }
    100% { top: 60px; left: 78%; opacity: 0; }
  }

  @media (max-width: 640px) {
    .kanban-demo {
      padding: 16px;
    }

    .kanban-card {
      font-size: 11px;
      padding: 6px 8px;
    }
  }
</style>
```

- [ ] **Step 2: Create Hero.astro**

```astro
---
// src/components/Hero.astro
import KanbanDemo from './KanbanDemo.astro';

const downloadUrl = '#'; // Placeholder — Lemon Squeezy URL goes here
---

<section class="hero">
  <div class="container">
    <div class="hero-content">
      <span class="hero-badge">For macOS</span>
      <h1 class="hero-title">Manage software projects<br />with AI agents</h1>
      <p class="hero-subtitle">Describe your tasks. Watch AI build it. No coding required.</p>
      <div class="hero-actions">
        <a href={downloadUrl} class="btn-primary">Download Free Trial</a>
        <a href="#how-it-works" class="btn-secondary">Watch Demo</a>
      </div>
    </div>
    <KanbanDemo />
  </div>
</section>

<style>
  .hero {
    padding-top: 96px;
    padding-bottom: 64px;
    text-align: center;
  }

  .hero-content {
    margin-bottom: 48px;
  }

  .hero-badge {
    display: inline-block;
    font-size: 12px;
    font-weight: 500;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    color: var(--color-text-muted);
    margin-bottom: 16px;
  }

  .hero-title {
    font-size: 48px;
    font-weight: 700;
    letter-spacing: -0.03em;
    line-height: 1.1;
    margin-bottom: 16px;
  }

  .hero-subtitle {
    font-size: 18px;
    color: var(--color-text-muted);
    max-width: 480px;
    margin: 0 auto 32px;
  }

  .hero-actions {
    display: flex;
    gap: 12px;
    justify-content: center;
  }

  .btn-primary {
    display: inline-block;
    font-size: 15px;
    font-weight: 500;
    color: white;
    background: var(--color-accent);
    padding: 10px 24px;
    border-radius: 10px;
    transition: background 0.15s;
  }

  .btn-primary:hover {
    background: var(--color-accent-hover);
  }

  .btn-secondary {
    display: inline-block;
    font-size: 15px;
    font-weight: 500;
    color: var(--color-text-muted);
    border: 1px solid var(--color-border);
    padding: 10px 24px;
    border-radius: 10px;
    transition: border-color 0.15s, color 0.15s;
  }

  .btn-secondary:hover {
    border-color: var(--color-text-muted);
    color: var(--color-text);
  }

  @media (max-width: 640px) {
    .hero-title {
      font-size: 32px;
    }

    .hero-subtitle {
      font-size: 16px;
    }

    .hero-actions {
      flex-direction: column;
      align-items: center;
    }
  }
</style>
```

- [ ] **Step 3: Add Hero to index.astro**

Replace `src/pages/index.astro`:

```astro
---
import Layout from '../layouts/Layout.astro';
import Nav from '../components/Nav.astro';
import Hero from '../components/Hero.astro';
---

<Layout>
  <Nav />
  <main>
    <Hero />
  </main>
</Layout>
```

- [ ] **Step 4: Build and verify**

```bash
npx astro build
```

Expected: Build succeeds. Hero section renders with headline, CTAs, and animated kanban board.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add hero section with animated kanban demo"
```

---

### Task 5: Value Propositions Component

**Files:**
- Create: `src/components/ValueProps.astro`
- Modify: `src/pages/index.astro`

- [ ] **Step 1: Create ValueProps.astro**

```astro
---
// src/components/ValueProps.astro
const props = [
  {
    title: 'Visual Project Board',
    description: 'Drag tasks, watch progress. No terminal, no jargon.',
  },
  {
    title: 'AI Workers, Not Chat',
    description: 'Assign tasks to AI agents that build real code autonomously.',
  },
  {
    title: 'Private & Local',
    description: 'Runs on your Mac. Your code stays on your machine.',
  },
];
---

<section class="value-props">
  <div class="container">
    <h2 class="section-title">Why Maestro?</h2>
    <div class="props-grid">
      {props.map((prop) => (
        <div class="prop-card">
          <h3 class="prop-title">{prop.title}</h3>
          <p class="prop-desc">{prop.description}</p>
        </div>
      ))}
    </div>
  </div>
</section>

<style>
  .value-props {
    border-top: 1px solid var(--color-border);
  }

  .section-title {
    text-align: center;
    font-size: 28px;
    font-weight: 700;
    letter-spacing: -0.02em;
    margin-bottom: 40px;
  }

  .props-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 20px;
  }

  .prop-card {
    background: var(--color-bg-subtle);
    border: 1px solid var(--color-border);
    border-radius: 12px;
    padding: 28px 24px;
  }

  .prop-title {
    font-size: 16px;
    font-weight: 600;
    margin-bottom: 8px;
  }

  .prop-desc {
    font-size: 14px;
    color: var(--color-text-muted);
    line-height: 1.5;
  }

  @media (max-width: 768px) {
    .props-grid {
      grid-template-columns: 1fr;
      gap: 12px;
    }
  }
</style>
```

- [ ] **Step 2: Add ValueProps to index.astro**

Replace `src/pages/index.astro`:

```astro
---
import Layout from '../layouts/Layout.astro';
import Nav from '../components/Nav.astro';
import Hero from '../components/Hero.astro';
import ValueProps from '../components/ValueProps.astro';
---

<Layout>
  <Nav />
  <main>
    <Hero />
    <ValueProps />
  </main>
</Layout>
```

- [ ] **Step 3: Build and verify**

```bash
npx astro build
```

Expected: Build succeeds. Three value prop cards render below the hero.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add value propositions section"
```

---

### Task 6: How It Works Component

**Files:**
- Create: `src/components/HowItWorks.astro`
- Modify: `src/pages/index.astro`

- [ ] **Step 1: Create HowItWorks.astro**

```astro
---
// src/components/HowItWorks.astro
const steps = [
  {
    number: '1',
    title: 'Describe',
    description: 'Write what you want in plain English',
  },
  {
    number: '2',
    title: 'Dispatch',
    description: 'AI agents pick up tasks and start building',
  },
  {
    number: '3',
    title: 'Review',
    description: 'See what changed, approve or roll back',
  },
];
---

<section id="how-it-works" class="how-it-works">
  <div class="container">
    <h2 class="section-title">How It Works</h2>
    <div class="steps">
      {steps.map((step, i) => (
        <>
          <div class="step">
            <div class="step-number">{step.number}</div>
            <h3 class="step-title">{step.title}</h3>
            <p class="step-desc">{step.description}</p>
          </div>
          {i < steps.length - 1 && <div class="step-arrow" aria-hidden="true" />}
        </>
      ))}
    </div>
  </div>
</section>

<style>
  .how-it-works {
    border-top: 1px solid var(--color-border);
  }

  .section-title {
    text-align: center;
    font-size: 28px;
    font-weight: 700;
    letter-spacing: -0.02em;
    margin-bottom: 48px;
  }

  .steps {
    display: flex;
    align-items: flex-start;
    justify-content: center;
    gap: 24px;
  }

  .step {
    text-align: center;
    flex: 0 1 200px;
  }

  .step-number {
    width: 40px;
    height: 40px;
    border-radius: 50%;
    background: var(--color-accent-subtle);
    color: var(--color-accent-hover);
    font-size: 18px;
    font-weight: 700;
    display: flex;
    align-items: center;
    justify-content: center;
    margin: 0 auto 12px;
  }

  .step-title {
    font-size: 16px;
    font-weight: 600;
    margin-bottom: 6px;
  }

  .step-desc {
    font-size: 14px;
    color: var(--color-text-muted);
    line-height: 1.4;
  }

  .step-arrow {
    flex-shrink: 0;
    width: 24px;
    height: 2px;
    background: var(--color-border);
    margin-top: 20px;
    position: relative;
  }

  .step-arrow::after {
    content: '';
    position: absolute;
    right: 0;
    top: -3px;
    width: 8px;
    height: 8px;
    border-right: 2px solid var(--color-border);
    border-top: 2px solid var(--color-border);
    transform: rotate(45deg);
  }

  @media (max-width: 640px) {
    .steps {
      flex-direction: column;
      align-items: center;
    }

    .step-arrow {
      width: 2px;
      height: 24px;
      margin-top: 0;
    }

    .step-arrow::after {
      right: -3px;
      top: auto;
      bottom: 0;
      transform: rotate(135deg);
    }
  }
</style>
```

- [ ] **Step 2: Add HowItWorks to index.astro**

Replace `src/pages/index.astro`:

```astro
---
import Layout from '../layouts/Layout.astro';
import Nav from '../components/Nav.astro';
import Hero from '../components/Hero.astro';
import ValueProps from '../components/ValueProps.astro';
import HowItWorks from '../components/HowItWorks.astro';
---

<Layout>
  <Nav />
  <main>
    <Hero />
    <ValueProps />
    <HowItWorks />
  </main>
</Layout>
```

- [ ] **Step 3: Build and verify**

```bash
npx astro build
```

Expected: Build succeeds. Three numbered steps with arrows render below value props.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add how-it-works section"
```

---

### Task 7: Pricing Component

**Files:**
- Create: `src/components/Pricing.astro`
- Modify: `src/pages/index.astro`

- [ ] **Step 1: Create Pricing.astro**

```astro
---
// src/components/Pricing.astro
const downloadUrl = '#'; // Placeholder — Lemon Squeezy URL goes here

const features = [
  '3-day free trial, full-featured',
  'Free updates for 1 year',
  'No account required',
  'No telemetry or tracking',
  'Source-available on GitHub',
];
---

<section id="pricing" class="pricing">
  <div class="container">
    <h2 class="section-title">Pricing</h2>
    <div class="pricing-card">
      <div class="price">$49</div>
      <p class="price-sub">One-time purchase. No subscription.</p>
      <ul class="features">
        {features.map((f) => (
          <li>{f}</li>
        ))}
      </ul>
      <a href={downloadUrl} class="btn-primary">Download Free Trial</a>
    </div>
    <p class="pricing-note">
      Requires a Claude API key (typically $5-20/month). Maestro guides you through setup.
    </p>
  </div>
</section>

<style>
  .pricing {
    border-top: 1px solid var(--color-border);
  }

  .section-title {
    text-align: center;
    font-size: 28px;
    font-weight: 700;
    letter-spacing: -0.02em;
    margin-bottom: 40px;
  }

  .pricing-card {
    max-width: 360px;
    margin: 0 auto;
    background: var(--color-bg-subtle);
    border: 1px solid var(--color-border-accent);
    border-radius: 16px;
    padding: 40px 32px;
    text-align: center;
  }

  .price {
    font-size: 56px;
    font-weight: 700;
    letter-spacing: -0.03em;
    line-height: 1;
    margin-bottom: 8px;
  }

  .price-sub {
    font-size: 15px;
    color: var(--color-text-muted);
    margin-bottom: 28px;
  }

  .features {
    list-style: none;
    text-align: left;
    margin-bottom: 28px;
  }

  .features li {
    font-size: 14px;
    color: var(--color-text-muted);
    padding: 6px 0;
    border-bottom: 1px solid var(--color-border);
  }

  .features li:last-child {
    border-bottom: none;
  }

  .btn-primary {
    display: inline-block;
    font-size: 15px;
    font-weight: 500;
    color: white;
    background: var(--color-accent);
    padding: 10px 24px;
    border-radius: 10px;
    transition: background 0.15s;
  }

  .btn-primary:hover {
    background: var(--color-accent-hover);
  }

  .pricing-note {
    text-align: center;
    font-size: 13px;
    color: var(--color-text-faint);
    margin-top: 20px;
  }
</style>
```

- [ ] **Step 2: Add Pricing to index.astro**

Replace `src/pages/index.astro`:

```astro
---
import Layout from '../layouts/Layout.astro';
import Nav from '../components/Nav.astro';
import Hero from '../components/Hero.astro';
import ValueProps from '../components/ValueProps.astro';
import HowItWorks from '../components/HowItWorks.astro';
import Pricing from '../components/Pricing.astro';
---

<Layout>
  <Nav />
  <main>
    <Hero />
    <ValueProps />
    <HowItWorks />
    <Pricing />
  </main>
</Layout>
```

- [ ] **Step 3: Build and verify**

```bash
npx astro build
```

Expected: Build succeeds. Pricing card renders centered with feature list and CTA.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add pricing section"
```

---

### Task 8: FAQ Component

**Files:**
- Create: `src/components/FAQ.astro`
- Modify: `src/pages/index.astro`

- [ ] **Step 1: Create FAQ.astro**

```astro
---
// src/components/FAQ.astro
const questions = [
  {
    q: 'Do I need to know how to code?',
    a: "No. Maestro is designed for non-developers. You describe what you want, AI agents write the code.",
  },
  {
    q: 'What does the AI API cost?',
    a: 'Maestro uses Claude by Anthropic. API usage typically costs $5-20/month depending on how much you build. Maestro guides you through setup on first launch.',
  },
  {
    q: 'Is my code private?',
    a: 'Yes. Everything runs locally on your Mac. Your code never leaves your machine.',
  },
  {
    q: 'What happens after the trial?',
    a: 'The app enters read-only mode. You can still view your projects, export code, and see history. No work is held hostage. Purchase to keep building.',
  },
  {
    q: 'Can I build [X] with this?',
    a: "If a developer could build it, Maestro's AI agents can attempt it. Best for web apps, APIs, scripts, and tools.",
  },
  {
    q: 'What if I need help?',
    a: 'Support via GitHub Discussions and email. Community-driven, searchable, and free.',
  },
];
---

<section id="faq" class="faq">
  <div class="container">
    <h2 class="section-title">FAQ</h2>
    <div class="faq-list">
      {questions.map((item) => (
        <div class="faq-item">
          <h3 class="faq-question">{item.q}</h3>
          <p class="faq-answer">{item.a}</p>
        </div>
      ))}
    </div>
  </div>
</section>

<style>
  .faq {
    border-top: 1px solid var(--color-border);
  }

  .section-title {
    text-align: center;
    font-size: 28px;
    font-weight: 700;
    letter-spacing: -0.02em;
    margin-bottom: 40px;
  }

  .faq-list {
    max-width: 600px;
    margin: 0 auto;
  }

  .faq-item {
    padding: 20px 0;
    border-bottom: 1px solid var(--color-border);
  }

  .faq-item:last-child {
    border-bottom: none;
  }

  .faq-question {
    font-size: 16px;
    font-weight: 600;
    margin-bottom: 8px;
  }

  .faq-answer {
    font-size: 14px;
    color: var(--color-text-muted);
    line-height: 1.5;
  }
</style>
```

- [ ] **Step 2: Add FAQ to index.astro**

Replace `src/pages/index.astro`:

```astro
---
import Layout from '../layouts/Layout.astro';
import Nav from '../components/Nav.astro';
import Hero from '../components/Hero.astro';
import ValueProps from '../components/ValueProps.astro';
import HowItWorks from '../components/HowItWorks.astro';
import Pricing from '../components/Pricing.astro';
import FAQ from '../components/FAQ.astro';
---

<Layout>
  <Nav />
  <main>
    <Hero />
    <ValueProps />
    <HowItWorks />
    <Pricing />
    <FAQ />
  </main>
</Layout>
```

- [ ] **Step 3: Build and verify**

```bash
npx astro build
```

Expected: Build succeeds. Six FAQ items render as a clean list below pricing.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add FAQ section"
```

---

### Task 9: Footer Component

**Files:**
- Create: `src/components/Footer.astro`
- Modify: `src/pages/index.astro`

- [ ] **Step 1: Create Footer.astro**

```astro
---
// src/components/Footer.astro
const year = new Date().getFullYear();
---

<footer class="footer">
  <div class="container footer-inner">
    <span class="footer-copy">{year} Maestro</span>
    <div class="footer-links">
      <a href="https://github.com/user/maestro" target="_blank" rel="noopener noreferrer">GitHub</a>
      <a href="https://github.com/user/maestro/discussions" target="_blank" rel="noopener noreferrer">Support</a>
      <a href="/privacy">Privacy</a>
    </div>
  </div>
</footer>

<style>
  .footer {
    border-top: 1px solid var(--color-border);
    padding: 24px 0;
  }

  .footer-inner {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .footer-copy {
    font-size: 13px;
    color: var(--color-text-faint);
  }

  .footer-links {
    display: flex;
    gap: 20px;
  }

  .footer-links a {
    font-size: 13px;
    color: var(--color-text-faint);
    transition: color 0.15s;
  }

  .footer-links a:hover {
    color: var(--color-text);
  }

  @media (max-width: 480px) {
    .footer-inner {
      flex-direction: column;
      gap: 12px;
    }
  }
</style>
```

- [ ] **Step 2: Add Footer to index.astro — final page assembly**

Replace `src/pages/index.astro`:

```astro
---
import Layout from '../layouts/Layout.astro';
import Nav from '../components/Nav.astro';
import Hero from '../components/Hero.astro';
import ValueProps from '../components/ValueProps.astro';
import HowItWorks from '../components/HowItWorks.astro';
import Pricing from '../components/Pricing.astro';
import FAQ from '../components/FAQ.astro';
import Footer from '../components/Footer.astro';
---

<Layout>
  <Nav />
  <main>
    <Hero />
    <ValueProps />
    <HowItWorks />
    <Pricing />
    <FAQ />
  </main>
  <Footer />
</Layout>
```

- [ ] **Step 3: Build and verify**

```bash
npx astro build
```

Expected: Build succeeds. Footer renders at the bottom with year, links.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add footer, complete page assembly"
```

---

### Task 10: Final Build Verification and OG Image Placeholder

**Files:**
- Create: `public/og-image.png` (placeholder)

- [ ] **Step 1: Create a placeholder OG image**

Create a simple 1200x630 SVG-based placeholder (browsers handle SVG in og:image poorly, so create a minimal PNG or reference the SVG for now):

```bash
cat > public/og-image.svg << 'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <rect width="1200" height="630" fill="#0a0a0f"/>
  <text x="600" y="280" font-size="64" font-weight="bold" fill="#e4e4e7" text-anchor="middle" font-family="-apple-system, sans-serif">Maestro</text>
  <text x="600" y="340" font-size="24" fill="#71717a" text-anchor="middle" font-family="-apple-system, sans-serif">Manage software projects with AI agents</text>
</svg>
SVGEOF
```

Note: Replace with a proper PNG render before launch. Update the og:image meta tag in Layout.astro to reference `/og-image.svg` for now.

- [ ] **Step 2: Update Layout.astro og:image path**

In `src/layouts/Layout.astro`, change the og:image lines:

```astro
<meta property="og:image" content={`${canonicalURL}/og-image.svg`} />
```

and

```astro
<meta name="twitter:image" content={`${canonicalURL}/og-image.svg`} />
```

- [ ] **Step 3: Full production build and size check**

```bash
cd /Users/pedrohm/workspace/projects/maestro-site
npx astro build
du -sh dist/
find dist/ -type f | head -20
```

Expected: Build succeeds. Total dist size well under 100KB. Output is pure HTML/CSS, no JS bundles.

- [ ] **Step 4: Preview the final site**

```bash
npx astro preview
```

Expected: Full page renders at localhost — nav, hero with animated kanban, value props, how it works, pricing, FAQ, footer. All anchor links work. Responsive on resize.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add OG image placeholder, verify production build"
```
