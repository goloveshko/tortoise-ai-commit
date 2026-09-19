# Tortoise AI Commit 🐢✨

> A lightweight **TortoiseGit Start-Commit hook** that automatically generates clean, informative commit messages in **Conventional Commits** (`conventional+body`) format using any OpenAI-compatible AI backend (local Ollama, LM Studio, OpenAI, OpenRouter, etc.).

---

## 🌟 Key Features

- 🎯 **Native TortoiseGit Integration:** Automatically pre-fills the TortoiseGit commit message area when you open the commit dialog.
- 🔌 **Universal OpenAI-Compatible API:** Works seamlessly with local models via **Ollama** or **LM Studio**, as well as cloud providers like **OpenAI**, **OpenRouter**, or **Groq**.
- 📋 **Conventional Commits Format:** Generates standard `type(scope): summary` followed by clean bullet points (`- `).
- 🧹 **Smart Draft & Scratchpad Filter:** Easily exclude untracked drafts, notes, or scratchpads using customizable glob patterns (`$AI_EXCLUDE`).
- 📁 **Selective Staging Support:** If specific files are selected in Windows Explorer or already staged in the Git index, only their diff is sent to the LLM.
- 🌐 **Bilingual Support:** Supports both English (`en`) and Russian (`ru`) commit generation out of the box.
- 🛠️ **PowerShell 5.1 Mojibake Auto-Fix:** Contains built-in UTF-8 byte reconstruction to prevent Windows PowerShell encoding bugs with Cyrillic or special characters.
- 📝 **External System Prompt:** Customize prompt instructions via `prompt.txt` without modifying the core script.

---

## 📂 Project Structure

```text
tortoise-ai-commit/
├── ai-commit.ps1              # Main hook script
├── environment.example.ps1    # Configuration template (rename to environment.ps1)
├── prompt.txt                 # Customizable system prompt
├── .gitignore                 # Excludes local secrets (environment.ps1)
├── LICENSE                    # MIT License
└── README.md
```

---

## 🚀 Installation & Setup

### Step 1: Clone or Download the Repository

Clone this repository to a stable directory on your machine (e.g., `C:\Tools\tortoise-ai-commit`):

```bash
git clone https://github.com/goloveshko/tortoise-ai-commit.git C:\Tools\tortoise-ai-commit
```

### Step 2: Configure Environment

1. In the project folder, duplicate `environment.example.ps1` and rename it to **`environment.ps1`**.
2. Open `environment.ps1` in any text editor:
   - Choose your provider (local **Ollama**, **LM Studio**, or **OpenAI** API key).
   - Set `$AI_LANGUAGE = "en"` (or `"ru"`).
   - Adjust `$AI_EXCLUDE` patterns for your draft files if needed.

> 💡 **Recommended local model:** [`qwen2.5-coder:7b`](https://ollama.com/library/qwen2.5-coder). It is fast, lightweight, and excels at understanding Git diffs.

### Step 3: Configure TortoiseGit Hook

1. Right-click anywhere in Windows Explorer and open **TortoiseGit → Settings**.
2. In the left navigation tree, select **Hook Scripts**.
3. Click the **Add...** button:
   - **Hook Type:** Select `Start Commit Hook`.
   - **Run when working tree path is under:** Enter `*` *(an asterisk applies the hook to all repositories)* or specify a specific repository path.
   - **Command Line To Execute:**
     ```cmd
     powershell.exe -ExecutionPolicy Bypass -File "C:\Tools\tortoise-ai-commit\ai-commit.ps1"
     ```
     *(⚠️ Make sure to use your actual path to `ai-commit.ps1`. Do NOT append `%1` or `%2` — TortoiseGit appends them automatically).*
   - **Wait for the script to finish:** ✅ Checked.
   - **Hide the script while running:** ✅ Checked.
   - **Enable:** ✅ Checked (at the top of the dialog).
4. Click **OK** and **Apply**.

---

## ⏱️ How It Works & What to Expect

1. When you right-click and choose **Git Commit...**, TortoiseGit triggers the hook script *before* displaying the commit window.
2. **Note on Execution Delay:** 
   > The commit window will take **2 to 6 seconds** to appear. This delay occurs because the hook synchronously gathers the Git diff, queries the LLM, and writes the response into TortoiseGit's message buffer before the dialog is rendered.
3. The TortoiseGit window opens with the commit summary and detailed bullet points already populated.
4. You can edit, adjust, or completely replace the generated message before pressing **Commit**.

---

## ⚙️ Customization

### Customizing the System Prompt
You can modify `prompt.txt` to enforce custom team guidelines or different commit conventions. 

- Keep `{{LANG_INSTRUCTION}}` in `prompt.txt` if you want the script to dynamically swap language instructions based on `$AI_LANGUAGE` in `environment.ps1`.
- If `prompt.txt` is missing or deleted, the script automatically falls back to an internal default prompt.

### Selective Diffs & Ignoring Drafts
- **Selected Files:** If you highlight specific files in Windows Explorer before clicking *Git Commit...*, only those files are analyzed.
- **Staged Files:** If files are already staged (`git add`), the script prioritizes staged changes (`git diff --cached`).
- **Exclude Patterns:** Add filename patterns to `$AI_EXCLUDE` in `environment.ps1` (e.g., `*.scratch.*`, `temp.log`) to keep work-in-progress code out of the diff sent to the AI.

---

## ❓ Troubleshooting

### The commit message is blank or shows `# [AI Error]`
If the AI server is unavailable or times out, the script will write an error explanation directly into the commit text box (e.g., `# [AI Error]: Unable to connect to server`).
- If using **Ollama**, verify that it is running (`ollama list` or check the system tray).
- Check that the model specified in `environment.ps1` is pulled and available (`ollama pull qwen2.5-coder:7b`).
- Check your network connectivity or API key if using cloud providers.

### Execution Policy Error
If PowerShell scripts are restricted on your system, ensure that the execution parameter `-ExecutionPolicy Bypass` is included in the TortoiseGit hook command line:
```cmd
powershell.exe -ExecutionPolicy Bypass -File "C:\Path\To\ai-commit.ps1"
```

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).

---

## ☕ Support & Feedback

Developed with ❤️ by a professional C++ & Qt developer.

- **Telegram Support Bot**: [@itz2bot](https://t.me/itz2bot?start=ai_commit_readme)
- **Portfolio**: [sergey.is-a.dev](https://sergey.is-a.dev)
- **GitHub Issues**: [Report a bug](https://github.com/goloveshko/tortoise-ai-commit/issues)