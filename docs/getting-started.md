# Getting Started with Maestro

Maestro lets you manage software projects using AI agents. You describe what you want built, and AI agents do the coding for you. This guide walks you through building Maestro from source and using it to create your first project.

---

## What You'll Need

| Requirement | How to Get It |
|---|---|
| A Mac running macOS 14 (Sonoma) or later | Check: Apple menu > About This Mac |
| Xcode 16 or later | Free from the [Mac App Store](https://apps.apple.com/app/xcode/id497799835) |
| Homebrew (package manager) | Run: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| XcodeGen | Run: `brew install xcodegen` |
| Claude CLI (the AI engine) | See [Step 2](#step-2-install-claude-cli) below |
| An Anthropic API key | See [Step 3](#step-3-get-your-api-key) below |

---

## Step 1: Build Maestro

Open Terminal (search "Terminal" in Spotlight) and run these commands one at a time:

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/maestro.git
cd maestro

# Generate the Xcode project from the config file
xcodegen generate

# Build the app
xcodebuild -scheme Maestro -configuration Release build
```

If the build succeeds, you'll see `** BUILD SUCCEEDED **`. The app is now at:

```
build/Build/Products/Release/Maestro.app
```

Drag `Maestro.app` to your Applications folder. You can also open the project in Xcode (`open Maestro.xcodeproj`) and hit Cmd+R to run it directly.

**Troubleshooting:**

- **"xcodegen: command not found"** — Run `brew install xcodegen` first.
- **"Unable to open mach-O at path... RenderBox"** — This is a harmless Xcode warning. Ignore it.
- **"No such module 'Semaphore'"** — Dependencies download automatically on first build. Try building again.
- **Build fails with signing errors** — Open `Maestro.xcodeproj` in Xcode, go to the Maestro target > Signing & Capabilities, and select your personal team.

---

## Step 2: Install Claude CLI

Claude CLI is the AI engine that Maestro uses to work on your tasks. Install it by following the official instructions:

1. Go to https://docs.anthropic.com/en/docs/claude-code/overview
2. Install Claude CLI using the instructions for your system
3. Verify it works by running:

```bash
claude --version
```

You should see a version number. If you get "command not found", the installation didn't complete — check the install instructions again.

---

## Step 3: Get Your API Key

Maestro uses Claude through the Anthropic API, which charges per use. Typical cost is $5-20/month depending on how much you use it.

1. Go to [console.anthropic.com](https://console.anthropic.com) and create an account
2. Add a payment method (Settings > Billing)
3. Go to **API Keys** in your dashboard
4. Click **Create Key** and copy it — it starts with `sk-ant-`

Now add it to your shell profile so Claude can find it. In Terminal:

```bash
echo 'export ANTHROPIC_API_KEY="sk-ant-YOUR-KEY-HERE"' >> ~/.zshrc
source ~/.zshrc
```

Replace `sk-ant-YOUR-KEY-HERE` with your actual key. To verify it worked:

```bash
echo $ANTHROPIC_API_KEY
```

You should see your key printed back.

---

## Step 4: Launch Maestro and Configure

1. Open Maestro from your Applications folder (or run it from Xcode)
2. Go to **Settings** (Cmd+,) > **General**
3. Under **Claude CLI**, click **Detect** — it should find Claude and show the path in green
4. Click **Save**

If Detect doesn't find Claude, click **Browse** and manually select the `claude` binary (usually at `/usr/local/bin/claude` or `/opt/homebrew/bin/claude`).

---

## Step 5: Create Your First Project

A "project" in Maestro is a folder on your Mac where the AI agents will write code. You need a folder ready — ideally an empty git repository.

### Set up the folder

```bash
# Create a folder for your project
mkdir ~/my-first-app
cd ~/my-first-app

# Initialize git (Maestro uses git to track changes)
git init
```

### Create the project in Maestro

1. Click the **+** button in the sidebar (or Cmd+N when no project is selected)
2. Enter a **name** (e.g., "My First App")
3. For **Workspace Path**, click Browse and select `~/my-first-app`
4. Click **Create**

### Configure the project

1. Select your project in the sidebar
2. Go to **Project Settings** (Cmd+4)
3. Set these fields:
   - **Workspace Root**: Should already be `~/my-first-app`
   - **Default Branch**: `main`
   - **Workspace Strategy**: Choose "Shared" (simpler for one-task-at-a-time)
   - **Dispatch Mode**: "Manual" (you decide when to run the AI)
   - **Max Turns**: 25 (gives the agent more room to work)

Leave the rest as defaults for now.

---

## Step 6: Create a Task

Tasks tell the AI what to build. Think of them as instructions you'd give a developer.

1. Make sure your project is selected in the sidebar
2. Press **Cmd+N** to create a new task
3. Fill in:
   - **Title**: A short name (e.g., "Create a landing page")
   - **Description**: Be specific about what you want. The more detail, the better the result.

### Writing good task descriptions

Good descriptions tell the agent what to build, what it should look like, and what tech to use.

**Bad:**
> Make a website

**Good:**
> Create a single-page landing page for a dog walking business called "Happy Paws."
>
> The page should have:
> - A hero section with a headline, subheadline, and a "Book Now" button
> - A section listing 3 services (Daily Walks, Weekend Adventures, Puppy Sitting) with icons
> - A pricing section with 3 tiers ($15/walk, $25/adventure, $40/sitting)
> - A contact form at the bottom (name, email, message)
> - A footer with social media links
>
> Use HTML, CSS, and vanilla JavaScript. Make it responsive. Use a modern, clean design with a green and white color scheme.

---

## Step 7: Run the Agent

1. Select your task on the Kanban board
2. In the task detail panel on the right, click **Run Agent**
3. Switch to the **Activity** tab (Cmd+2) to watch the agent work

You'll see the agent:
- Read your task description
- Plan its approach
- Create files, write code, run commands
- Test its work
- Report back when done

When the agent finishes, your task automatically moves to the **Review** column.

---

## Step 8: Check the Results

After the agent completes:

1. Open your project folder to see the files the agent created:
   ```bash
   ls ~/my-first-app
   ```

2. If it built a website, you can open the HTML file directly:
   ```bash
   open ~/my-first-app/index.html
   ```

3. Check the git history to see what the agent did:
   ```bash
   cd ~/my-first-app
   git log --oneline
   ```

4. If you're happy, drag the task to **Done** on the Kanban board
5. If you want changes, create a new follow-up task describing what to fix

---

## Tips

**Break big projects into small tasks.** Instead of "Build me a full e-commerce store," create separate tasks: "Create the product listing page," "Add a shopping cart," "Build the checkout flow." Smaller tasks get better results.

**Use the Workflow Prompt for project-wide instructions.** In Project Settings, the "Workflow Prompt" field lets you set instructions that apply to every task. Good things to put here:
- "This is a React/Next.js project. Use TypeScript."
- "Always use Tailwind CSS for styling."
- "Write clean, well-commented code."
- "Create a README.md explaining how to run the project."

**Set a budget limit.** In Project Settings, set "Max Budget USD" to something like $2.00 per task while you're learning. This prevents accidentally running up costs.

**Run multiple agents at once.** If you have several independent tasks, you can run agents on all of them simultaneously. The "Max Concurrent Agents" setting controls how many run in parallel (default: 3).

**Use the Resume button.** If an agent's work is interrupted or you want it to continue where it left off, click **Resume** instead of Run. This picks up the same session.

---

## Project Ideas to Try

Here are some things you can build with Maestro to get started:

- **Personal website** — A portfolio page with your bio, projects, and contact info
- **Todo app** — A simple task manager with add, complete, and delete functionality
- **Recipe book** — A web page that displays your favorite recipes with ingredients and steps
- **Expense tracker** — A form that logs expenses and shows totals by category
- **Quiz game** — A trivia game with multiple choice questions and a score counter

Start simple, see how the agent works, then take on bigger projects as you get comfortable.

---

## Useful Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| Cmd+1 | Kanban Board |
| Cmd+2 | Agent Activity |
| Cmd+3 | Gantt Chart |
| Cmd+4 | Project Settings |
| Cmd+N | New Task |
| Cmd+, | App Settings |

---

## Getting Help

- **Agent seems stuck?** Click "Cancel Agent" and try again with a clearer task description.
- **Build issues?** Make sure Xcode 16+ and XcodeGen 2.35+ are installed.
- **Claude not found?** Run `which claude` in Terminal to verify the CLI is installed.
- **API errors?** Check that your `ANTHROPIC_API_KEY` is set correctly: `echo $ANTHROPIC_API_KEY`
- **Agent not writing files?** Make sure the Workspace Root in Project Settings points to a valid directory.
